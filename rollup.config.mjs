import resolve from "@rollup/plugin-node-resolve";
import commonjs from "@rollup/plugin-commonjs";
import babel from "rollup-plugin-babel";
import { terser } from "rollup-plugin-terser";
import autoExternal from 'rollup-plugin-auto-external';

let plugins = [
  autoExternal({
    builtins: true,
    dependencies: false,
    peerDependencies: false
  }),

  babel(),

  // so Rollup can find externals
  resolve({ extensions: ["ts", ".js"], preferBuiltins: true }),

  // so Rollup can convert externals to an ES module
  commonjs(),
];

// minify only in production mode
if (process.env.NODE_ENV === "production") {
  plugins.push(
    // minify
    terser({
      ecma: 2018,
      warnings: true,
      compress: {
        drop_console: false,
      },
    })
  );
}

export default [
  {
    input: "src/fs-plus.mjs",
    output: [
      {
        dir: "lib",
        format: "cjs",
        sourcemap: true,
      },
    ],
    plugins: plugins,
  }
];
