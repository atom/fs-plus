path = require 'path'
temp = require 'temp'
fs = require '../lib/fs-plus'

temp.track()

describe "fs", ->
  fixturesDir = path.join(__dirname, 'fixtures')
  sampleFile = path.join(fixturesDir,  'sample.js')
  linkToSampleFile = path.join(fixturesDir,  'link-to-sample.js')
  try
    fs.unlinkSync(linkToSampleFile)
  fs.symlinkSync(sampleFile, linkToSampleFile, 'junction')

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
      expect(fs.isSymbolicLinkSync(linkToSampleFile)).toBe true

    it "returns false with a file path", ->
      expect(fs.isSymbolicLinkSync(sampleFile)).toBe false

    it "returns false with a non-existent path", ->
      expect(fs.isSymbolicLinkSync(path.join(fixturesDir, 'non-existent'))).toBe false
      expect(fs.isSymbolicLinkSync('')).toBe false
      expect(fs.isSymbolicLinkSync(null)).toBe false

  describe ".isSymbolicLink(path, callback)", ->
    it "calls back with true for a symbolic link path", ->
      callback = jasmine.createSpy('isSymbolicLink')
      fs.isSymbolicLink(linkToSampleFile, callback)
      waitsFor -> callback.callCount is 1
      runs -> expect(callback.mostRecentCall.args[0]).toBe true

    it "calls back with false for a file path", ->
      callback = jasmine.createSpy('isSymbolicLink')
      fs.isSymbolicLink(sampleFile, callback)
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

    it "throws an error when the provided path is a file", ->
      tempDir = temp.mkdirSync('fs-plus-')
      filePath = path.join(tempDir, 'file.txt')
      fs.writeFileSync(filePath, '')
      expect(fs.isFileSync(filePath)).toBe true

      makeTreeError = null

      try
        fs.makeTreeSync(filePath)
      catch error
        makeTreeError = error

      expect(makeTreeError.code).toBe 'EEXIST'
      expect(makeTreeError.path).toBe filePath

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

    it "calls back with an error when the provided path is a file", ->
      callback = jasmine.createSpy('callback')
      tempDir = temp.mkdirSync('fs-plus-')
      filePath = path.join(tempDir, 'file.txt')
      fs.writeFileSync(filePath, '')
      expect(fs.isFileSync(filePath)).toBe true

      fs.makeTree(filePath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(callback.argsForCall[0][0]).toBeTruthy()
        expect(callback.argsForCall[0][1]).toBeUndefined()
        expect(callback.argsForCall[0][0].code).toBe 'EEXIST'
        expect(callback.argsForCall[0][0].path).toBe filePath

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
      unless process.platform is 'win32' # Dir symlinks on Windows require admin
        directory = temp.mkdirSync('symlink-in-here')
        paths = []
        onPath = (childPath) -> paths.push(childPath)
        fs.symlinkSync(path.join(directory, 'source'), path.join(directory, 'destination'))
        fs.traverseTreeSync(directory, onPath)
        expect(paths.length).toBe 0

  describe ".traverseTree(path, onFile, onDirectory, onDone)", ->
    it "calls fn for every path in the tree at the given path", ->
      paths = []
      onPath = (childPath) ->
        paths.push(childPath)
        true
      done = false
      onDone = ->
        done = true
      fs.traverseTree fixturesDir, onPath, onPath, onDone

      waitsFor ->
        done

      runs ->
        expect(paths).toEqual fs.listTreeSync(fixturesDir)

    it "does not recurse into a directory if it is pruned", ->
      paths = []
      onPath = (childPath) ->
        if childPath.match(/\/dir$/)
          false
        else
          paths.push(childPath)
          true
      done = false
      onDone = ->
        done = true

      fs.traverseTree fixturesDir, onPath, onPath, onDone

      waitsFor ->
        done

      runs ->
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

      symlinkDone = false
      onSymlinkPathDone = ->
        symlinkDone = true

      regularDone = false
      onRegularPathDone = ->
        regularDone = true

      fs.traverseTree symlinkPath, onSymlinkPath, onSymlinkPath, onSymlinkPathDone
      fs.traverseTree regularPath, onPath, onPath, onRegularPathDone

      waitsFor ->
        symlinkDone && regularDone

      runs ->
        expect(symlinkPaths).toEqual(paths)

    it "ignores missing symlinks", ->
      directory = temp.mkdirSync('symlink-in-here')
      paths = []
      onPath = (childPath) -> paths.push(childPath)
      fs.symlinkSync(path.join(directory, 'source'), path.join(directory, 'destination'))
      done = false
      onDone = ->
        done = true
      fs.traverseTree directory, onPath, onPath, onDone
      waitsFor ->
        done
      runs ->
        expect(paths.length).toBe 0

  describe ".traverseTree(path, onFile, onDirectory, onDone)", ->
    it "calls fn for every path in the tree at the given path", ->
      paths = []
      onPath = (childPath) ->
        paths.push(childPath)
        true
      done = false
      onDone = ->
        done = true
      fs.traverseTree fixturesDir, onPath, onPath, onDone

      waitsFor ->
        done

      runs ->
        expect(paths).toEqual fs.listTreeSync(fixturesDir)

    it "does not recurse into a directory if it is pruned", ->
      paths = []
      onPath = (childPath) ->
        if childPath.match(/\/dir$/)
          false
        else
          paths.push(childPath)
          true
      done = false
      onDone = ->
        done = true

      fs.traverseTree fixturesDir, onPath, onPath, onDone

      waitsFor ->
        done

      runs ->
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

      symlinkDone = false
      onSymlinkPathDone = ->
        symlinkDone = true

      regularDone = false
      onRegularPathDone = ->
        regularDone = true

      fs.traverseTree symlinkPath, onSymlinkPath, onSymlinkPath, onSymlinkPathDone
      fs.traverseTree regularPath, onPath, onPath, onRegularPathDone

      waitsFor ->
        symlinkDone && regularDone

      runs ->
        expect(symlinkPaths).toEqual(paths)

    it "ignores missing symlinks", ->
      directory = temp.mkdirSync('symlink-in-here')
      paths = []
      onPath = (childPath) -> paths.push(childPath)
      fs.symlinkSync(path.join(directory, 'source'), path.join(directory, 'destination'))
      done = false
      onDone = ->
        done = true
      fs.traverseTree directory, onPath, onPath, onDone
      waitsFor ->
        done
      runs ->
        expect(paths.length).toBe 0

  describe ".md5ForPath(path)", ->
    it "returns the MD5 hash of the file at the given path", ->
      expect(fs.md5ForPath(require.resolve('./fixtures/binary-file.png'))).toBe 'cdaad7483b17865b5f00728d189e90eb'

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

    it "returns the Application Support path on Mac", ->
      Object.defineProperty process, 'platform', value: 'darwin'
      unless process.env.HOME
        Object.defineProperty process.env, 'HOME', value: path.join(path.sep, 'Users', 'Buzz')
      expect(fs.getAppDataDirectory()).toBe path.join(fs.getHomeDirectory(), 'Library', 'Application Support')

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
      expect(fs.getSizeSync(path.join(fixturesDir, 'binary-file.png'))).toBe 392
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

  describe ".copyFileSync(sourceFilePath, destinationFilePath)", ->
    it "copies the specified file", ->
      sourceFilePath = temp.path()
      destinationFilePath = path.join(temp.path(), '/unexisting-dir/foo.bar')
      content = ''
      content += 'ABCDE' for i in [0...20000] by 1
      fs.writeFileSync(sourceFilePath, content)
      fs.copyFileSync(sourceFilePath, destinationFilePath)
      expect(fs.readFileSync(destinationFilePath, 'utf8')).toBe(fs.readFileSync(sourceFilePath, 'utf8'))

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

    it "returns false when passed \\", ->
      expect(fs.isAbsolute('\\')).toBe false

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

  describe ".tildify(pathToTildify)", ->
    getHomeDirectory = null

    beforeEach ->
      getHomeDirectory = fs.getHomeDirectory

    afterEach ->
      fs.getHomeDirectory = getHomeDirectory

    it "tildifys the path on Linux and macOS", ->
      return if process.platform is 'win32'

      home = fs.getHomeDirectory()

      expect(fs.tildify(home)).toBe '~'
      expect(fs.tildify(path.join(home, 'foo'))).toBe '~/foo'
      fixture = path.join('foo', home)
      expect(fs.tildify(fixture)).toBe fixture
      fixture = path.resolve("#{home}foo", 'tildify')
      expect(fs.tildify(fixture)).toBe fixture
      expect(fs.tildify('foo')).toBe 'foo'

    it "does not tildify if home is unset", ->
      return if process.platform is 'win32'

      home = fs.getHomeDirectory()
      fs.getHomeDirectory = -> return undefined

      fixture = path.join(home, 'foo')
      expect(fs.tildify(fixture)).toBe fixture

    it "doesn't change URLs or paths not tildified", ->
      urlToLeaveAlone = "https://atom.io/something/fun?abc"
      expect(fs.tildify(urlToLeaveAlone)).toBe urlToLeaveAlone

      pathToLeaveAlone = "/Library/Support/Atom/State"
      expect(fs.tildify(pathToLeaveAlone)).toBe pathToLeaveAlone

  describe ".move", ->
    tempDir = null

    beforeEach ->
      tempDir = temp.mkdirSync('fs-plus-')

    it 'calls back with an error if the source does not exist', ->
      callback = jasmine.createSpy('callback')
      directoryPath = path.join(tempDir, 'subdir')
      newDirectoryPath = path.join(tempDir, 'subdir2', 'subdir2')

      fs.move(directoryPath, newDirectoryPath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(callback.argsForCall[0][0]).toBeTruthy()
        expect(callback.argsForCall[0][0].code).toBe 'ENOENT'

    it 'calls back with an error if the target already exists', ->
      callback = jasmine.createSpy('callback')
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'subdir2')
      fs.mkdirSync(newDirectoryPath)

      fs.move(directoryPath, newDirectoryPath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(callback.argsForCall[0][0]).toBeTruthy()
        expect(callback.argsForCall[0][0].code).toBe 'EEXIST'

    it 'renames if the target just has different letter casing', ->
      callback = jasmine.createSpy('callback')
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'SUBDIR')

      fs.move(directoryPath, newDirectoryPath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        # If the filesystem is case-insensitive, the old directory should still exist.
        expect(fs.existsSync(directoryPath)).toBe fs.isCaseInsensitive()
        expect(fs.existsSync(newDirectoryPath)).toBe true

    it 'renames to a target with an existent parent directory', ->
      callback = jasmine.createSpy('callback')
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'subdir2')

      fs.move(directoryPath, newDirectoryPath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(fs.existsSync(directoryPath)).toBe false
        expect(fs.existsSync(newDirectoryPath)).toBe true

    it 'renames to a target with a non-existent parent directory', ->
      callback = jasmine.createSpy('callback')
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'subdir2/subdir2')

      fs.move(directoryPath, newDirectoryPath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(fs.existsSync(directoryPath)).toBe false
        expect(fs.existsSync(newDirectoryPath)).toBe true

    it 'renames files', ->
      callback = jasmine.createSpy('callback')
      filePath = path.join(tempDir, 'subdir')
      fs.writeFileSync(filePath, '')
      newFilePath = path.join(tempDir, 'subdir2')

      fs.move(filePath, newFilePath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(fs.existsSync(filePath)).toBe false
        expect(fs.existsSync(newFilePath)).toBe true

  describe ".moveSync", ->
    tempDir = null

    beforeEach ->
      tempDir = temp.mkdirSync('fs-plus-')

    it 'throws an error if the source does not exist', ->
      directoryPath = path.join(tempDir, 'subdir')
      newDirectoryPath = path.join(tempDir, 'subdir2', 'subdir2')

      expect(-> fs.moveSync(directoryPath, newDirectoryPath)).toThrow()

    it 'throws an error if the target already exists', ->
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'subdir2')
      fs.mkdirSync(newDirectoryPath)

      expect(-> fs.moveSync(directoryPath, newDirectoryPath)).toThrow()

    it 'renames if the target just has different letter casing', ->
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'SUBDIR')

      fs.moveSync(directoryPath, newDirectoryPath)

      # If the filesystem is case-insensitive, the old directory should still exist.
      expect(fs.existsSync(directoryPath)).toBe fs.isCaseInsensitive()
      expect(fs.existsSync(newDirectoryPath)).toBe true

    it 'renames to a target with an existent parent directory', ->
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'subdir2')

      fs.moveSync(directoryPath, newDirectoryPath)

      expect(fs.existsSync(directoryPath)).toBe false
      expect(fs.existsSync(newDirectoryPath)).toBe true

    it 'renames to a target with a non-existent parent directory', ->
      directoryPath = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryPath)
      newDirectoryPath = path.join(tempDir, 'subdir2/subdir2')

      fs.moveSync(directoryPath, newDirectoryPath)

      expect(fs.existsSync(directoryPath)).toBe false
      expect(fs.existsSync(newDirectoryPath)).toBe true

    it 'renames files', ->
      filePath = path.join(tempDir, 'subdir')
      fs.writeFileSync(filePath, '')
      newFilePath = path.join(tempDir, 'subdir2')

      fs.moveSync(filePath, newFilePath)

      expect(fs.existsSync(filePath)).toBe false
      expect(fs.existsSync(newFilePath)).toBe true

  describe '.isBinaryExtension', ->
    it 'returns true for a recognized binary file extension', ->
      expect(fs.isBinaryExtension('.DS_Store')).toBe true

    it 'returns false for non-binary file extension', ->
      expect(fs.isBinaryExtension('.bz2')).toBe false

    it 'returns true for an uppercase binary file extension', ->
      expect(fs.isBinaryExtension('.EXE')).toBe true

  describe ".isCompressedExtension", ->
    it 'returns true for a recognized compressed file extension', ->
      expect(fs.isCompressedExtension('.bz2')).toBe true

    it 'returns false for non-compressed file extension', ->
      expect(fs.isCompressedExtension('.jpg')).toBe false

  describe '.isImageExtension', ->
    it 'returns true for a recognized image file extension', ->
      expect(fs.isImageExtension('.jpg')).toBe true

    it 'returns false for non-image file extension', ->
      expect(fs.isImageExtension('.bz2')).toBe false

  describe '.isMarkdownExtension', ->
    it 'returns true for a recognized Markdown file extension', ->
      expect(fs.isMarkdownExtension('.md')).toBe true

    it 'returns false for non-Markdown file extension', ->
      expect(fs.isMarkdownExtension('.bz2')).toBe false

    it 'returns true for a recognised Markdown file extension with unusual capitalisation', ->
      expect(fs.isMarkdownExtension('.MaRKdOwN')).toBe true

  describe '.isPdfExtension', ->
    it 'returns true for a recognized PDF file extension', ->
      expect(fs.isPdfExtension('.pdf')).toBe true

    it 'returns false for non-PDF file extension', ->
      expect(fs.isPdfExtension('.bz2')).toBe false

    it 'returns true for an uppercase PDF file extension', ->
      expect(fs.isPdfExtension('.PDF')).toBe true

  describe '.isReadmePath', ->
    it 'returns true for a recognized README path', ->
      expect(fs.isReadmePath('./path/to/README.md')).toBe true

    it 'returns false for non README path', ->
      expect(fs.isReadmePath('./path/foo.txt')).toBe false
