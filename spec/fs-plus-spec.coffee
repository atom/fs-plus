path = require 'path'
temp = require 'temp'
fs = require '../src/fs-plus'

temp.track()

describe "fs", ->
  fixturesDir = path.join(__dirname, 'fixtures')

  describe ".isFileSync(path)", ->
    it "returns true with a file path", ->
      expect(fs.isFileSync(path.join(fixturesDir,  'sample.js'))).toBe true

    it "returns false with a directory path", ->
      expect(fs.isFileSync(fixturesDir)).toBe false

    it "returns false with a non-existent path", ->
      expect(fs.isFileSync(path.join(fixturesDir, 'non-existent'))).toBe false
      expect(fs.isFileSync(null)).toBe false

  describe ".isSymbolicLinkSync(path)", ->
    it "returns true with a symbolic link path", ->
      expect(fs.isSymbolicLinkSync(path.join(fixturesDir,  'link-to-sample.js'))).toBe true

    it "returns false with a file path", ->
      expect(fs.isSymbolicLinkSync(path.join(fixturesDir,  'sample.js'))).toBe false

    it "returns false with a non-existent path", ->
      expect(fs.isSymbolicLinkSync(path.join(fixturesDir, 'non-existent'))).toBe false
      expect(fs.isSymbolicLinkSync('')).toBe false
      expect(fs.isSymbolicLinkSync(null)).toBe false

  describe ".isSymbolicLink(path, callback)", ->
    it "calls back with true for a symbolic link path", ->
      callback = jasmine.createSpy('isSymbolicLink')
      fs.isSymbolicLink(path.join(fixturesDir,  'link-to-sample.js'), callback)
      waitsFor -> callback.callCount is 1
      runs -> expect(callback.mostRecentCall.args[0]).toBe true

    it "calls back with false for a file path", ->
      callback = jasmine.createSpy('isSymbolicLink')
      fs.isSymbolicLink(path.join(fixturesDir,  'sample.js'), callback)
      waitsFor -> callback.callCount is 1
      runs -> expect(callback.mostRecentCall.args[0]).toBe false

    it "calls back with false for a non-existent path", ->
      callback = jasmine.createSpy('isSymbolicLink')

      fs.isSymbolicLink(path.join(fixturesDir,  'non-existent'), callback)
      waitsFor -> callback.callCount is 1
      runs ->
        expect(callback.mostRecentCall.args[0]).toBe false

        callback.reset()
        fs.isSymbolicLink('', callback)

      waitsFor -> callback.callCount is 1
      runs ->
        expect(callback.mostRecentCall.args[0]).toBe false

        callback.reset()
        fs.isSymbolicLink(null, callback)

      waitsFor -> callback.callCount is 1
      runs -> expect(callback.mostRecentCall.args[0]).toBe false

  describe ".existsSync(path)", ->
    it "returns true when the path exists", ->
      expect(fs.existsSync(fixturesDir)).toBe true

    it "returns false when the path doesn't exist", ->
      expect(fs.existsSync(path.join(fixturesDir, "-nope-does-not-exist"))).toBe false
      expect(fs.existsSync("")).toBe false
      expect(fs.existsSync(null)).toBe false

  describe ".remove(pathToRemove, callback)", ->
    tempDir = null

    beforeEach ->
      tempDir = temp.mkdirSync('fs-plus-')

    it "removes an existing file", ->
      filePath = path.join(tempDir, 'existing-file')
      fs.writeFileSync(filePath, '')

      done = false
      fs.remove filePath, ->
        done = true

      waitsFor ->
        done

      runs ->
        expect(fs.existsSync(filePath)).toBe false

    it "does nothing for a non-existent file", ->
      filePath = path.join(tempDir, 'non-existent-file')

      done = false
      fs.remove filePath, ->
        done = true

      waitsFor ->
        done

      runs ->
        expect(fs.existsSync(filePath)).toBe false

    it "removes a non-empty directory", ->
      directoryPath = path.join(tempDir, 'subdir')
      fs.makeTreeSync(path.join(directoryPath, 'subdir'))

      done = false
      fs.remove directoryPath, ->
        done = true

      waitsFor ->
        done

      runs ->
        expect(fs.existsSync(directoryPath)).toBe false

  describe ".makeTreeSync(path)", ->
    aPath = path.join(temp.dir, 'a')

    beforeEach ->
      fs.removeSync(aPath) if fs.existsSync(aPath)

    it "creates all directories in path including any missing parent directories", ->
      abcPath = path.join(aPath, 'b', 'c')
      fs.makeTreeSync(abcPath)
      expect(fs.isDirectorySync(abcPath)).toBeTruthy()

  describe ".makeTree(path)", ->
    aPath = path.join(temp.dir, 'a')

    beforeEach ->
      fs.removeSync(aPath) if fs.existsSync(aPath)

    it "creates all directories in path including any missing parent directories", ->
      callback = jasmine.createSpy('callback')
      abcPath = path.join(aPath, 'b', 'c')
      fs.makeTree(abcPath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(callback.argsForCall[0][0]).toBeNull()
        expect(fs.isDirectorySync(abcPath)).toBeTruthy()

        fs.makeTree(abcPath, callback)

      waitsFor ->
        callback.callCount is 2

      runs ->
        expect(callback.argsForCall[1][0]).toBeUndefined()
        expect(fs.isDirectorySync(abcPath)).toBeTruthy()

  describe ".traverseTreeSync(path, onFile, onDirectory)", ->
    it "calls fn for every path in the tree at the given path", ->
      paths = []
      onPath = (childPath) ->
        paths.push(childPath)
        true
      expect(fs.traverseTreeSync(fixturesDir, onPath, onPath)).toBeUndefined()
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

    it "returns alphabetically sorted paths (lowercase first)", ->
      paths = fs.listSync(fixturesDir)
      sortedPaths = [
        path.join(fixturesDir, 'binary-file.png')
        path.join(fixturesDir, 'coffee.coffee')
        path.join(fixturesDir, 'css.css')
        path.join(fixturesDir, 'link-to-sample.js')
        path.join(fixturesDir, 'sample.js')
        path.join(fixturesDir, 'Sample.markdown')
        path.join(fixturesDir, 'sample.txt')
        path.join(fixturesDir, 'test.cson')
        path.join(fixturesDir, 'test.json')
        path.join(fixturesDir, 'Xample.md')
      ]
      expect(sortedPaths).toEqual paths

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

  describe ".getAppDataDirectory", ->
    originalPlatform = null

    beforeEach ->
      originalPlatform = process.platform

    afterEach ->
      Object.defineProperty process, 'platform', value: originalPlatform

    it "returns a Application Support path on Mac", ->
      Object.defineProperty process, 'platform', value: 'darwin'
      expect(fs.getAppDataDirectory()).toBe path.join(process.env.HOME, 'Library', 'Application Support')

    it "returns %AppData% on Windows", ->
      Object.defineProperty process, 'platform', value: 'win32'
      unless process.env.APPDATA
        Object.defineProperty process.env, 'APPDATA', value: 'C:\\Users\\test\\AppData\\Roaming'
      expect(fs.getAppDataDirectory()).toBe process.env.APPDATA

    it "returns /var/lib on linux", ->
      Object.defineProperty process, 'platform', value: 'linux'
      expect(fs.getAppDataDirectory()).toBe '/var/lib'

    it "returns null on other platforms", ->
      Object.defineProperty process, 'platform', value: 'foobar'
      expect(fs.getAppDataDirectory()).toBe null

  describe ".getSizeSync(pathToCheck)", ->
    it "returns the size of the file at the path", ->
      expect(fs.getSizeSync()).toBe -1
      expect(fs.getSizeSync('')).toBe -1
      expect(fs.getSizeSync(null)).toBe -1
      expect(fs.getSizeSync(fixturesDir)).toBeGreaterThan 0
      expect(fs.getSizeSync(path.join(fixturesDir, 'sample.js'))).toBe 408
      expect(fs.getSizeSync(path.join(fixturesDir, 'does.not.exist'))).toBe -1

  describe ".writeFileSync(filePath)", ->
    it "creates any missing parent directories", ->
      directory = temp.mkdirSync('fs-plus-')
      file = path.join(directory, 'a', 'b', 'c.txt')
      expect(fs.existsSync(path.dirname(file))).toBeFalsy()

      fs.writeFileSync(file, 'contents')
      expect(fs.readFileSync(file, 'utf8')).toBe 'contents'
      expect(fs.existsSync(path.dirname(file))).toBeTruthy()

  describe ".writeFile(filePath)", ->
    it "creates any missing parent directories", ->
      directory = temp.mkdirSync('fs-plus-')
      file = path.join(directory, 'a', 'b', 'c.txt')
      expect(fs.existsSync(path.dirname(file))).toBeFalsy()

      handler = jasmine.createSpy('writeFileHandler')
      fs.writeFile(file, 'contents', handler)

      waitsFor ->
        handler.callCount is 1

      runs ->
        expect(fs.readFileSync(file, 'utf8')).toBe 'contents'
        expect(fs.existsSync(path.dirname(file))).toBeTruthy()

  describe ".copySync(sourcePath, destinationPath)", ->
    [source, destination] = []

    beforeEach ->
      source = temp.mkdirSync('fs-plus-')
      destination = temp.mkdirSync('fs-plus-')

    describe "with just files", ->
      beforeEach ->
        fs.writeFileSync(path.join(source, 'a.txt'), 'a')
        fs.copySync(source, destination)

      it "copies the file", ->
        expect(fs.isFileSync(path.join(destination, 'a.txt'))).toBeTruthy()

    describe "with folders and files", ->
      beforeEach ->
        fs.writeFileSync(path.join(source, 'a.txt'), 'a')
        fs.makeTreeSync(path.join(source, 'b'))
        fs.copySync(source, destination)

      it "copies the file and folder", ->
        expect(fs.isFileSync(path.join(destination, 'a.txt'))).toBeTruthy()
        expect(fs.isDirectorySync(path.join(destination, 'b'))).toBeTruthy()

      describe "source is copied into itself", ->
        beforeEach ->
          source = temp.mkdirSync('fs-plus-')
          destination = source
          fs.writeFileSync(path.join(source, 'a.txt'), 'a')
          fs.makeTreeSync(path.join(source, 'b'))
          fs.copySync(source, path.join(destination, path.basename(source)))

        it "copies the directory once", ->
          expect(fs.isDirectorySync(path.join(destination, path.basename(source)))).toBeTruthy()
          expect(fs.isDirectorySync(path.join(destination, path.basename(source), 'b'))).toBeTruthy()
          expect(fs.isDirectorySync(path.join(destination, path.basename(source), path.basename(source)))).toBeFalsy()

  describe ".isCaseSensitive()/isCaseInsensitive()", ->
    it "does not return the same value for both", ->
      expect(fs.isCaseInsensitive()).not.toBe fs.isCaseSensitive()

  describe ".resolve(loadPaths, pathToResolve, extensions)", ->
    it "returns the resolved path or undefined if it does not exist", ->
      expect(fs.resolve(fixturesDir, 'sample.js')).toBe path.join(fixturesDir, 'sample.js')
      expect(fs.resolve(fixturesDir, 'sample', ['js'])).toBe path.join(fixturesDir, 'sample.js')
      expect(fs.resolve(fixturesDir, 'sample', ['abc', 'txt'])).toBe path.join(fixturesDir, 'sample.txt')
      expect(fs.resolve(fixturesDir)).toBe fixturesDir

      expect(fs.resolve()).toBeUndefined()
      expect(fs.resolve(fixturesDir, 'sample', ['badext'])).toBeUndefined()
      expect(fs.resolve(fixturesDir, 'doesnotexist.js')).toBeUndefined()
      expect(fs.resolve(fixturesDir, undefined)).toBeUndefined()
      expect(fs.resolve(fixturesDir, 3)).toBeUndefined()
      expect(fs.resolve(fixturesDir, false)).toBeUndefined()
      expect(fs.resolve(fixturesDir, null)).toBeUndefined()
      expect(fs.resolve(fixturesDir, '')).toBeUndefined()

  describe ".isAbsolute(pathToCheck)", ->
    originalPlatform = null

    beforeEach ->
      originalPlatform = process.platform

    afterEach ->
      Object.defineProperty process, 'platform', value: originalPlatform

    it "returns true when the path is absolute, false otherwise", ->
      Object.defineProperty process, 'platform', value: 'win32'

      expect(fs.isAbsolute()).toBe false
      expect(fs.isAbsolute(null)).toBe false
      expect(fs.isAbsolute('')).toBe false
      expect(fs.isAbsolute('test')).toBe false
      expect(fs.isAbsolute('a\\b')).toBe false
      expect(fs.isAbsolute('/a/b/c')).toBe false
      expect(fs.isAbsolute('\\\\server\\share')).toBe true
      expect(fs.isAbsolute('C:\\Drive')).toBe true

      Object.defineProperty process, 'platform', value: 'linux'

      expect(fs.isAbsolute()).toBe false
      expect(fs.isAbsolute(null)).toBe false
      expect(fs.isAbsolute('')).toBe false
      expect(fs.isAbsolute('test')).toBe false
      expect(fs.isAbsolute('a/b')).toBe false
      expect(fs.isAbsolute('\\\\server\\share')).toBe false
      expect(fs.isAbsolute('C:\\Drive')).toBe false
      expect(fs.isAbsolute('/')).toBe true
      expect(fs.isAbsolute('/a/b/c')).toBe true

  describe ".normalize(pathToNormalize)", ->
    it "normalizes the path", ->
      expect(fs.normalize()).toBe null
      expect(fs.normalize(null)).toBe null
      expect(fs.normalize(true)).toBe 'true'
      expect(fs.normalize('')).toBe '.'
      expect(fs.normalize(3)).toBe '3'
      expect(fs.normalize('a')).toBe 'a'
      expect(fs.normalize('a/b/c/../d')).toBe path.join('a', 'b', 'd')
      expect(fs.normalize('./a')).toBe 'a'
      expect(fs.normalize('~')).toBe fs.getHomeDirectory()
      expect(fs.normalize('~/foo')).toBe path.join(fs.getHomeDirectory(), 'foo')
