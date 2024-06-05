const esbuild = require('esbuild');

esbuild.build({
  entryPoints: ['src-js/index.ts'],
  bundle: true,
  outfile: 'public-js/package.js',
  format: 'esm',
  minify: true,
}).catch(() => process.exit(1));
