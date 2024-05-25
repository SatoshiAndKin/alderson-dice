const path = require('path');

module.exports = {
  entry: './src-js/index.js',
  output: {
    filename: 'bundle.js',
    path: path.resolve(__dirname, 'public'),
  },
  mode: 'development',
  devtool: 'eval-source-map',
};

