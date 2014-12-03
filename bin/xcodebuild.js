var xcodebuild = require('../lib/xcodebuild');

// xcodebuild
//     .build({
//         project: '/Users/josa/tmp/xcode-test/TEST.xcodeproj',
//         configuration: 'Debug',
//         sdk: 'iphonesimulator8.1'
//     }, function() {
//
//     });

// xcodebuild
//     .list({
//         project: '/Users/josa/tmp/xcode-test/TEST.xcodeproj',
//     }, function(list) {
//          console.log(list);
//     });

xcodebuild
    .targets({
        project: '/Users/josa/tmp/xcode-test/TEST.xcodeproj',
    }, function(targets) {
         console.log('');
         console.log('Targets');
         console.log(targets);
    });

xcodebuild
    .configurations({
        project: '/Users/josa/tmp/xcode-test/TEST.xcodeproj',
    }, function(configurations) {
        console.log('');
        console.log('Configurations');
        console.log(configurations);
    });


xcodebuild
    .sdks({
        project: '/Users/josa/tmp/xcode-test/TEST.xcodeproj',
    }, function(sdks) {
        console.log('');
        console.log('SDKs');
        console.log(sdks);
    });
