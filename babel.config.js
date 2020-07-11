let presets = [];

let plugins = [
  ["@babel/plugin-proposal-optional-chaining", { loose: false }],
  ["@babel/plugin-proposal-nullish-coalescing-operator", { loose: false }],

];

if (process.env.BABEL_ENV === "development") {
  plugins.push(...[
      "@babel/plugin-transform-modules-commonjs",
      "@babel/plugin-proposal-export-namespace-from",
  ]);
}

module.exports = {
  presets: presets,
  plugins: plugins,
  exclude: "node_modules/**",
  sourceMap: "inline",
};
