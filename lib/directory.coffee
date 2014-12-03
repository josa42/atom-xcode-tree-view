path = require 'path'

xcode = require 'xcode'
_ = require 'underscore-plus'
{CompositeDisposable, Emitter} = require 'event-kit'
fs = require 'fs-plus'
PathWatcher = require 'pathwatcher'
File = require './file'

realpathCache = {}

module.exports =
class Directory
  constructor: ({@name, fullPath, @symlink, @expandedEntries, @isExpanded, @isRoot, @ignoredPatterns, @xcodeProject, @xcodeGroup, @xcodeFile}) ->
    @emitter = new Emitter()
    @subscriptions = new CompositeDisposable()

    @path = fullPath
    @realPath = @path
    if fs.isCaseInsensitive()
      @lowerCasePath = @path.toLowerCase()
      @lowerCaseRealPath = @lowerCasePath

    @isRoot ?= false
    @isExpanded ?= false
    @expandedEntries ?= {}
    @status = null
    @entries = {}

    @submodule = atom.project.getRepo()?.isSubmodule(@path)

    @subscribeToRepo()
    @updateStatus()
    @loadRealPath()

  destroy: ->
    @unwatch()
    @subscriptions.dispose()
    @emitter.emit('did-destroy')

  onDidDestroy: (callback) ->
    @emitter.on('did-destroy', callback)

  onDidStatusChange: (callback) ->
    @emitter.on('did-status-change', callback)

  onDidAddEntries: (callback) ->
    @emitter.on('did-add-entries', callback)

  onDidRemoveEntries: (callback) ->
    @emitter.on('did-remove-entries', callback)

  loadRealPath: ->
    fs.realpath @path, realpathCache, (error, realPath) =>
      if realPath and realPath isnt @path
        @realPath = realPath
        @lowerCaseRealPath = @realPath.toLowerCase() if fs.isCaseInsensitive()
        @updateStatus()

  # Subscribe to project's repo for changes to the Git status of this directory.
  subscribeToRepo: ->
    repo = atom.project.getRepo()
    return unless repo?

    @subscriptions.add repo.onDidChangeStatus (event) =>
      @updateStatus(repo) if event.path.indexOf("#{@path}#{path.sep}") is 0
    @subscriptions.add repo.onDidChangeStatuses =>
      @updateStatus(repo)

  # Update the status property of this directory using the repo.
  updateStatus: ->
    repo = atom.project.getRepo()
    return unless repo?

    newStatus = null
    if repo.isPathIgnored(@path)
      newStatus = 'ignored'
    else
      status = repo.getDirectoryStatus(@path)
      if repo.isStatusModified(status)
        newStatus = 'modified'
      else if repo.isStatusNew(status)
        newStatus = 'added'

    if newStatus isnt @status
      @status = newStatus
      @emitter.emit('did-status-change', newStatus)

  # Is the given path ignored?
  isPathIgnored: (filePath) ->
    if atom.config.get('tree-view.hideVcsIgnoredFiles')
      repo = atom.project.getRepo()
      return true if repo? and repo.isProjectAtRoot() and repo.isPathIgnored(filePath)

    if atom.config.get('tree-view.hideIgnoredNames')
      for ignoredPattern in @ignoredPatterns
        return true if ignoredPattern.match(filePath)

    false

  # Does given full path start with the given prefix?
  isPathPrefixOf: (prefix, fullPath) ->
    fullPath.indexOf(prefix) is 0 and fullPath[prefix.length] is path.sep

  isPathEqual: (pathToCompare) ->
    @path is pathToCompare or @realPath is pathToCompare

  # Public: Does this directory contain the given path?
  #
  # See atom.Directory::contains for more details.
  contains: (pathToCheck) ->
    return false unless pathToCheck

    # Normalize forward slashes to back slashes on windows
    pathToCheck = pathToCheck.replace(/\//g, '\\') if process.platform is 'win32'

    if fs.isCaseInsensitive()
      directoryPath = @lowerCasePath
      pathToCheck = pathToCheck.toLowerCase()
    else
      directoryPath = @path

    return true if @isPathPrefixOf(directoryPath, pathToCheck)

    # Check real path
    if @realPath isnt @path
      if fs.isCaseInsensitive()
        directoryPath = @lowerCaseRealPath
      else
        directoryPath = @realPath

      return @isPathPrefixOf(directoryPath, pathToCheck)

    false

  # Public: Stop watching this directory for changes.
  unwatch: ->
    if @watchSubscription?
      @watchSubscription.close()
      @watchSubscription = null

    for key, entry of @entries
      entry.destroy()
      delete @entries[key]

  # Public: Watch this directory for changes.
  watch: ->
    try
      @watchSubscription ?= PathWatcher.watch @path, (eventType) =>
        switch eventType
          when 'change' then @reload()
          when 'delete' then @destroy()

  getEntries: ->

    directories = []
    files = []

    if @xcodeGroup

      PBXFileReference = @xcodeProject.hash.project.objects.PBXFileReference
      PBXGroup = @xcodeProject.hash.project.objects.PBXGroup
      PBXVariantGroup = @xcodeProject.hash.project.objects.PBXVariantGroup

      for child in @xcodeGroup.children

        file = PBXFileReference[child.value]
        group = PBXGroup[child.value]
        variantGroup = PBXVariantGroup[child.value]
        if variantGroup
          group = variantGroup

        if (group)
          fullPath = @path
          if group.path
            fullPath = path.join(fullPath, group.path)

          directories.push(new Directory({
            name: child.comment,
            fullPath,
            symlink: no,
            isExpanded: no,
            expandedEntries: [],
            @ignoredPatterns
            xcodeProject: @xcodeProject
            xcodeGroup: group
          }))
        else if file
          fullPath = @path
          if file.path
            fullPath = path.join(fullPath, file.path)

          files.push(new File({
            name:file.path,
            fullPath,
            symlink: no,
            realpathCache
          }))
        else
          console.error 'What is that?', child
    else
      try
        names = fs.readdirSync(@path)
      catch error
        names = []

      names = names
        .filter ((name) -> name.match /\.xcodeproj$/)
        .sort (name1, name2) ->
          name1.toLowerCase().localeCompare(name2.toLowerCase())

      for name in names
        pbpath = path.join @path, name, 'project.pbxproj'

        xcodeProject = xcode.project(pbpath).parseSync()
        PBXProject = xcodeProject.hash.project.objects.PBXProject
        PBXGroup = xcodeProject.hash.project.objects.PBXGroup

        projectGroups = Object.keys(PBXProject)
          .map (key) -> PBXProject[key]
          .map (project) -> project.mainGroup
          .filter (groupKey) -> groupKey
          .map (groupKey) -> PBXGroup[groupKey]

        for xcodeGroup in projectGroups

          fullPath = @path
          if xcodeGroup.path
            fullPath = path.join(fullPath, xcodeGroup.path)

          directories.push(new Directory({
            name: name.replace(/\.xcodeproj$/, ''),
            fullPath,
            symlink: no,
            isExpanded: no,
            expandedEntries: [],
            @ignoredPatterns,
            xcodeProject,
            xcodeGroup
          }))

    directories.concat files

  # Public: Perform a synchronous reload of the directory.
  reload: ->
    newEntries = []
    removedEntries = _.clone(@entries)
    index = 0

    for entry in @getEntries()
      if @entries.hasOwnProperty(entry)
        delete removedEntries[entry]
        index++
        continue

      entry.indexInParentDirectory = index
      index++
      newEntries.push(entry)

    entriesRemoved = false
    for name, entry of removedEntries
      entriesRemoved = true
      entry.destroy()
      delete @entries[name]
      delete @expandedEntries[name]
    @emitter.emit('did-remove-entries', removedEntries) if entriesRemoved

    if newEntries.length > 0
      @entries[entry.name] = entry for entry in newEntries
      @emitter.emit('did-add-entries', newEntries)

  # Public: Collapse this directory and stop watching it.
  collapse: ->
    @isExpanded = false
    @expandedEntries = @serializeExpansionStates()
    @unwatch()

  # Public: Expand this directory, load its children, and start watching it for
  # changes.
  expand: ->
    @isExpanded = true
    @reload()
    @watch()

  serializeExpansionStates: ->
    expandedEntries = {}
    for name, entry of @entries when entry.isExpanded
      expandedEntries[name] = entry.serializeExpansionStates()
    expandedEntries
