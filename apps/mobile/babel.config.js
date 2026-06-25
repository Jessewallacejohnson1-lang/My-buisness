module.exports = function (api) {
  api.cache(true)
  return {
    presets: [
      ['babel-preset-expo', { jsxImportSource: 'nativewind' }],
      'nativewind/babel',
    ],
    // react-native-worklets/plugin powers Reanimated v4 and must be listed last.
    plugins: ['react-native-worklets/plugin'],
  }
}
