import { createPlugins } from "rollup-plugin-atomic"

const plugins = createPlugins(["js", "babel"])

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
    // loaded externally
    external: ["atom"],
    plugins: plugins,
  },
]
