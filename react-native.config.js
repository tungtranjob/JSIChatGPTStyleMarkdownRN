const path = require('path');

/**
 * `modules/react-native-md-list` is a local library: declaring it here makes
 * autolinking pick it up on both platforms (Gradle include + CocoaPods) without
 * publishing it to npm.
 */
module.exports = {
  dependencies: {
    'react-native-md-list': {
      root: path.join(__dirname, 'modules/react-native-md-list'),
    },
  },
};
