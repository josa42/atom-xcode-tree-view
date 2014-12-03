spawn = require("child_process").spawn
execFile = require("child_process").execFile
steps =
  CompileC: "Compile"
  CompileStoryboard: "Compile"
  CompileXIB: "Compile"
  CompileAssetCatalog: "Compile"
  GenerateDSYMFile: "Generate (DSYM)"
  ProcessInfoPlistFile: "Process"
  Ld: "Link"


class XcodeBuild
  sdks: (options, callback) ->
    @runCmd "showsdks", options, (err, stdout, stderr) ->
      key = undefined
      list = stdout
        .split(/(\r?\n)/g)
        .filter (line) -> line.match(/SDKs:$/) or line.match(/^\t/)
        .map (line) -> line.replace(/\sSDKs:$/, "")
        .reduce(((all, line) ->
          match = line.match(/^\t([^\t]+)\t-sdk (.*)$/)
          unless match
            key = line
            all[key] = {}
          else
            all[key][match[2]] = match[1].replace(/\s*$/, "")
          all
        ), {})
      callback list

  targets: (options, callback) ->
    @list options, (list) ->
      callback list.Targets

  configurations: (options, callback) ->
    @list options, (list) ->
      callback list.Configurations

  list: (options, callback) ->
    @runCmd "list", options, (err, stdout, stderr) ->
      key = undefined
      list = stdout.split(/(\r?\n)/g)
        .filter (line) -> line.match /^    (    |(Targets|Build Configurations):)/
        .map (line) -> line.replace(/^    (    )?/, "").replace /^Build Configurations:$/, "Configurations:"
        .reduce(((all, line) ->
          keyMatch = line.match(/^([^:]+):$/)
          if keyMatch
            key = keyMatch[1]
            all[key] = []
          else
            all[key].push line
          all
        ), {})
      callback list

  runCmd: (cmd, options, callback) ->
    args = ["-#{cmd}"]
    Object.keys(options).forEach (key) ->
      args.push "-#{key}"
      args.push options[key]

    execFile "xcodebuild", args, callback

  build: (options, callback) ->
    proc = spawn("xcodebuild", [
      "-project"
      options.project
      "-configuration"
      options.configuration
      "-sdk"
      options.sdk
    ])
    proc.stdout.setEncoding "utf8"
    proc.stdout.on "data", (data) ->
      str = data.toString()
      lines = str.split(/(\r?\n)/g)
        .filter (line) -> line.match /^[^\s\*]/
        .map (line) ->
          match = line.match(/^(Create product structure|Write auxiliary files|Check dependencies|CompileAssetCatalog|ProcessInfoPlistFile|GenerateDSYMFile|CompileC|Ld|CompileStoryboard|CompileXIB|Touch)/)
          if match
            fileMatch = line.match(/\/([^\/\s]+)(\s[^\/]*)?$/)
            step = steps[match[1]] or match[1]
            return step + " => " + fileMatch[1]  if fileMatch
            step
        .filter (step) -> step
        .map (step) -> "* " + step

      console.log lines.join("\n")  if lines.length

    proc.on "close", (code) -> callback(code is 0) if callback

module.exports = new XcodeBuild()
