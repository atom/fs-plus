path = require 'path'
temp = require 'temp'
fs = require '../src/fs-plus'

describe "fs", ->
  fixturesDir = path.join(__dirname, 'fixtures')

  describe ".read(path)", ->
    it "return contents of file", ->
      expect(fs.read(require.resolve("./fixtures/sample.txt"))).toBe "Some text.\n"

    it "does not through an exception when the path is a binary file", ->
      expect(-> fs.read(require.resolve("./fixtures/binary-file.png"))).not.toThrow()

  describe ".isFileSync(path)", ->
    it "returns true with a file path", ->
      expect(fs.isFileSync(path.join(fixturesDir,  'sample.js'))).toBe true

    it "returns false with a directory path", ->
      expect(fs.isFileSync(fixturesDir)).toBe false

    it "returns false with a non-existent path", ->
      expect(fs.isFileSync(path.join(fixturesDir, 'non-existent'))).toBe false
      expect(fs.isFileSync(null)).toBe false

  describe ".exists(path)", ->
    it "returns true when path exsits", ->
      expect(fs.exists(fixturesDir)).toBe true

    it "returns false when path doesn't exsit", ->
      expect(fs.exists(path.join(fixturesDir, "-nope-does-not-exist"))).toBe false
      expect(fs.exists("")).toBe false
      expect(fs.exists(null)).toBe false

  describe ".makeTree(path)", ->
    aPath = path.join(temp.dir, 'a')

    beforeEach ->
      fs.remove(aPath) if fs.exists(aPath)

    it "creates all directories in path including any missing parent directories", ->
      abcPath = path.join(aPath, 'b', 'c')
      fs.makeTree(abcPath)
      expect(fs.exists(abcPath)).toBeTruthy()

  describe ".traverseTreeSync(path, onFile, onDirectory)", ->
    it "calls fn for every path in the tree at the given path", ->
      paths = []
      onPath = (childPath) ->
        paths.push(childPath)
        true
      fs.traverseTreeSync fixturesDir, onPath, onPath
      expect(paths).toEqual fs.listTreeSync(fixturesDir)

    it "does not recurse into a directory if it is pruned", ->
      paths = []
      onPath = (childPath) ->
        if childPath.match(/\/dir$/)
          false
        else
          paths.push(childPath)
          true
      fs.traverseTreeSync fixturesDir, onPath, onPath

      expect(paths.length).toBeGreaterThan 0
      for filePath in paths
        expect(filePath).not.toMatch /\/dir\//

    it "returns entries if path is a symlink", ->
      symlinkPath = path.join(fixturesDir, 'symlink-to-dir')
      symlinkPaths = []
      onSymlinkPath = (path) -> symlinkPaths.push(path.substring(symlinkPath.length + 1))

      regularPath = path.join(fixturesDir, 'dir')
      paths = []
      onPath = (path) -> paths.push(path.substring(regularPath.length + 1))

      fs.traverseTreeSync(symlinkPath, onSymlinkPath, onSymlinkPath)
      fs.traverseTreeSync(regularPath, onPath, onPath)

      expect(symlinkPaths).toEqual(paths)

    it "ignores missing symlinks", ->
      directory = temp.mkdirSync('symlink-in-here')
      paths = []
      onPath = (childPath) -> paths.push(childPath)
      fs.symlinkSync(path.join(directory, 'source'), path.join(directory, 'destination'))
      fs.traverseTreeSync(directory, onPath)
      expect(paths.length).toBe 0

  describe ".md5ForPath(path)", ->
    it "returns the MD5 hash of the file at the given path", ->
      expect(fs.md5ForPath(require.resolve('./fixtures/sample.js'))).toBe 'dd38087d0d7e3e4802a6d3f9b9745f2b'

  describe ".list(path, extensions)", ->
    it "returns the absolute paths of entries within the given directory", ->
      paths = fs.listSync(fixturesDir)
      expect(paths).toContain path.join(fixturesDir, 'css.css')
      expect(paths).toContain path.join(fixturesDir, 'coffee.coffee')
      expect(paths).toContain path.join(fixturesDir, 'sample.txt')
      expect(paths).toContain path.join(fixturesDir, 'sample.js')
      expect(paths).toContain path.join(fixturesDir, 'binary-file.png')

    it "returns an empty array for paths that aren't directories or don't exist", ->
      expect(fs.listSync(path.join(fixturesDir, 'sample.js'))).toEqual []
      expect(fs.listSync('/non/existent/directory')).toEqual []

    it "can filter the paths by an optional array of file extensions", ->
      paths = fs.listSync(fixturesDir, ['.css', 'coffee'])
      expect(paths).toContain path.join(fixturesDir, 'css.css')
      expect(paths).toContain path.join(fixturesDir, 'coffee.coffee')
      expect(listedPath).toMatch /(css|coffee)$/ for listedPath in paths

  describe ".list(path, [extensions,] callback)", ->
    paths = null

    it "calls the callback with the absolute paths of entries within the given directory", ->
      done = false
      fs.list fixturesDir, (err, result) ->
        paths = result
        done = true

      waitsFor ->
        done

      runs ->
        expect(paths).toContain path.join(fixturesDir, 'css.css')
        expect(paths).toContain path.join(fixturesDir, 'coffee.coffee')
        expect(paths).toContain path.join(fixturesDir, 'sample.txt')
        expect(paths).toContain path.join(fixturesDir, 'sample.js')
        expect(paths).toContain path.join(fixturesDir, 'binary-file.png')

    it "can filter the paths by an optional array of file extensions", ->
      done = false
      fs.list fixturesDir, ['css', '.coffee'], (err, result) ->
        paths = result
        done = true

      waitsFor ->
        done

      runs ->
        expect(paths).toContain path.join(fixturesDir, 'css.css')
        expect(paths).toContain path.join(fixturesDir, 'coffee.coffee')
        expect(listedPath).toMatch /(css|coffee)$/ for listedPath in paths

  describe ".absolute(relativePath)", ->
    it "converts a leading ~ segment to the HOME directory", ->
      homeDir = fs.getHomeDirectory()
      expect(fs.absolute('~')).toBe fs.realpathSync(homeDir)
      expect(fs.absolute(path.join('~', 'does', 'not', 'exist'))).toBe path.join(homeDir, 'does', 'not', 'exist')
      expect(fs.absolute('~test')).toBe '~test'

  describe ".getSizeSync(pathToCheck)", ->
    it "returns the size of the file at the path", ->
      expect(fs.getSizeSync()).toBe -1
      expect(fs.getSizeSync('')).toBe -1
      expect(fs.getSizeSync(null)).toBe -1
      expect(fs.getSizeSync(fixturesDir)).toBeGreaterThan 0
      expect(fs.getSizeSync(path.join(fixturesDir, 'sample.js'))).toBe 408
      expect(fs.getSizeSync(path.join(fixturesDir, 'does.not.exist'))).toBe -1
