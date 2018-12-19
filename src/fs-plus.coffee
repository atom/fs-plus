fs = require 'fs'
Module = require 'module'
path = require 'path'

_ = require 'underscore-plus'
async = require 'async'
mkdirp = require 'mkdirp'
rimraf = require 'rimraf'

# Public: Useful extensions to node's built-in fs module
#
# Important, this extends Node's builtin in ['fs' module][fs], which means that you
# can do anything that you can do with Node's 'fs' module plus a few extra
# functions that we've found to be helpful.
#
# [fs]: http://nodejs.org/api/fs.html
fsPlus =
  __esModule: false

  getHomeDirectory: ->
    if process.platform is 'win32' and not process.env.HOME
      process.env.USERPROFILE
    else
      process.env.HOME

  # Public: Make the given path absolute by resolving it against the current
  # working directory.
  #
  # relativePath - The {String} containing the relative path. If the path is
  #                prefixed with '~', it will be expanded to the current user's
  #                home directory.
  #
  # Returns the {String} absolute path or the relative path if it's unable to
  # determine its real path.
  absolute: (relativePath) ->
    return null unless relativePath?

    relativePath = fsPlus.resolveHome(relativePath)

    try
      fs.realpathSync(relativePath)
    catch e
      relativePath

  # Public: Normalize the given path treating a leading `~` segment as referring
  # to the home directory. This method does not query the filesystem.
  #
  # pathToNormalize - The {String} containing the abnormal path. If the path is
  #                   prefixed with '~', it will be expanded to the current
  #                   user's home directory.
  #
  # Returns a normalized path {String}.
  normalize: (pathToNormalize) ->
    return null unless pathToNormalize?

    fsPlus.resolveHome(path.normalize(pathToNormalize.toString()))

  resolveHome: (relativePath) ->
    if relativePath is '~'
      return fsPlus.getHomeDirectory()
    else if relativePath.indexOf("~#{path.sep}") is 0
      return "#{fsPlus.getHomeDirectory()}#{relativePath.substring(1)}"
    return relativePath

  # Public: Convert an absolute path to tilde path for Linux and macOS.
  # /Users/username/dev => ~/dev
  #
  # pathToTildify - The {String} containing the full path.
  #
  # Returns a tildified path {String}.
  tildify: (pathToTildify) ->
    return pathToTildify if process.platform is 'win32'

    normalized = fsPlus.normalize(pathToTildify)
    homeDir = fsPlus.getHomeDirectory()
    return pathToTildify unless homeDir?

    return '~' if normalized is homeDir
    return pathToTildify unless normalized.startsWith(path.join(homeDir, path.sep))

    path.join('~', path.sep, normalized.substring(homeDir.length + 1))

  # Public: Get path to store application specific data.
  #
  # Returns the {String} absolute path or null if platform isn't supported
  # Mac: ~/Library/Application Support/
  # Win: %AppData%
  # Linux: /var/lib
  getAppDataDirectory: ->
    switch process.platform
      when 'darwin' then fsPlus.absolute(path.join '~', 'Library', 'Application Support')
      when 'linux'  then '/var/lib'
      when 'win32'  then process.env.APPDATA
      else null

  # Public: Is the given path absolute?
  #
  # pathToCheck - The relative or absolute {String} path to check.
  #
  # Returns a {Boolean}, true if the path is absolute, false otherwise.
  isAbsolute: (pathToCheck='') ->
    if process.platform is 'win32'
      return true if pathToCheck[1] is ':' # C:\ style
      return true if pathToCheck[0] is '\\' and pathToCheck[1] is '\\' # \\server\share style
    else
      return pathToCheck[0] is '/' # /usr style

    false

  # Public: Returns true if a file or folder at the specified path exists.
  existsSync: (pathToCheck) ->
    isPathValid(pathToCheck) and (statSyncNoException(pathToCheck) isnt false)

  # Public: Returns true if the given path exists and is a directory.
  isDirectorySync: (directoryPath) ->
    return false unless isPathValid(directoryPath)
    if stat = statSyncNoException(directoryPath)
      stat.isDirectory()
    else
      false

  # Public: Asynchronously checks that the given path exists and is a directory.
  isDirectory: (directoryPath, done) ->
    return done(false) unless isPathValid(directoryPath)
    fs.stat directoryPath, (error, stat) ->
      if error?
        done(false)
      else
        done(stat.isDirectory())

  # Public: Returns true if the specified path exists and is a file.
  isFileSync: (filePath) ->
    return false unless isPathValid(filePath)
    if stat = statSyncNoException(filePath)
      stat.isFile()
    else
      false

  # Public: Returns true if the specified path is a symbolic link.
  isSymbolicLinkSync: (symlinkPath) ->
    return false unless isPathValid(symlinkPath)
    if stat = lstatSyncNoException(symlinkPath)
      stat.isSymbolicLink()
    else
      false

  # Public: Calls back with true if the specified path is a symbolic link.
  isSymbolicLink: (symlinkPath, callback) ->
    if isPathValid(symlinkPath)
      fs.lstat symlinkPath, (error, stat) ->
        callback?(stat? and stat.isSymbolicLink())
    else
      process.nextTick -> callback?(false)

  # Public: Returns true if the specified path is executable.
  isExecutableSync: (pathToCheck) ->
    return false unless isPathValid(pathToCheck)
    if stat = statSyncNoException(pathToCheck)
      (stat.mode & 0o777 & 1) isnt 0
    else
      false

  # Public: Returns the size of the specified path.
  getSizeSync: (pathToCheck) ->
    if isPathValid(pathToCheck)
      statSyncNoException(pathToCheck).size ? -1
    else
      -1

  # Public: Returns an Array with the paths of the files and directories
  # contained within the directory path. It is not recursive.
  #
  # rootPath - The absolute {String} path to the directory to list.
  # extensions - An {Array} of extensions to filter the results by. If none are
  #              given, none are filtered (optional).
  listSync: (rootPath, extensions) ->
    return [] unless fsPlus.isDirectorySync(rootPath)
    paths = fs.readdirSync(rootPath)
    paths = fsPlus.filterExtensions(paths, extensions) if extensions
    paths = paths.sort (a, b) -> a.toLowerCase().localeCompare(b.toLowerCase())
    paths = paths.map (childPath) -> path.join(rootPath, childPath)
    paths

  # Public: Asynchronously lists the files and directories in the given path.
  # The listing is not recursive.
  #
  # rootPath - The absolute {String} path to the directory to list.
  # extensions - An {Array} of extensions to filter the results by. If none are
  #              given, none are filtered (optional).
  # callback - The {Function} to call.
  list: (rootPath, rest...) ->
    extensions = rest.shift() if rest.length > 1
    done = rest.shift()
    fs.readdir rootPath, (error, paths) ->
      if error?
        done(error)
      else
        paths = fsPlus.filterExtensions(paths, extensions) if extensions
        paths = paths.sort (a, b) -> a.toLowerCase().localeCompare(b.toLowerCase())
        paths = paths.map (childPath) -> path.join(rootPath, childPath)
        done(null, paths)

  # Returns only the paths which end with one of the given extensions.
  filterExtensions: (paths, extensions) ->
    extensions = extensions.map (ext) ->
      if ext is ''
        ext
      else
        '.' + ext.replace(/^\./, '')
    paths.filter (pathToCheck) ->
      _.include(extensions, path.extname(pathToCheck))

  # Public: Get all paths under the given path.
  #
  # rootPath - The {String} path to start at.
  #
  # Return an {Array} of {String}s under the given path.
  listTreeSync: (rootPath) ->
    paths = []
    onPath = (childPath) ->
      paths.push(childPath)
      true
    fsPlus.traverseTreeSync(rootPath, onPath, onPath)
    paths

  # Public: Moves the source file or directory to the target asynchronously.
  move: (source, target, callback) ->
    isMoveTargetValid source, target, (isMoveTargetValidErr, isTargetValid) ->
      if isMoveTargetValidErr
        callback(isMoveTargetValidErr)
        return

      unless isTargetValid
        error = new Error("'#{target}' already exists.")
        error.code = 'EEXIST'
        callback(error)
        return

      targetParentPath = path.dirname(target)
      fs.exists targetParentPath, (targetParentExists) ->
        if targetParentExists
          fs.rename source, target, callback
          return

        fsPlus.makeTree targetParentPath, (makeTreeErr) ->
          if makeTreeErr
            callback(makeTreeErr)
            return

          fs.rename source, target, callback

  # Public: Moves the source file or directory to the target synchronously.
  moveSync: (source, target) ->
    unless isMoveTargetValidSync(source, target)
      error = new Error("'#{target}' already exists.")
      error.code = 'EEXIST'
      throw error

    targetParentPath = path.dirname(target)
    fsPlus.makeTreeSync(targetParentPath) unless fs.existsSync(targetParentPath)
    fs.renameSync(source, target)

  # Public: Removes the file or directory at the given path synchronously.
  removeSync: (pathToRemove) ->
    rimraf.sync(pathToRemove)

  # Public: Removes the file or directory at the given path asynchronously.
  remove: (pathToRemove, callback) ->
    rimraf(pathToRemove, callback)

  # Public: Open, write, flush, and close a file, writing the given content
  # synchronously.
  #
  # It also creates the necessary parent directories.
  writeFileSync: (filePath, content, options) ->
    mkdirp.sync(path.dirname(filePath))
    fs.writeFileSync(filePath, content, options)

  # Public: Open, write, flush, and close a file, writing the given content
  # asynchronously.
  #
  # It also creates the necessary parent directories.
  writeFile: (filePath, content, options, callback) ->
    callback = _.last(arguments)
    mkdirp path.dirname(filePath), (error) ->
      if error?
        callback?(error)
      else
        fs.writeFile(filePath, content, options, callback)

  # Public: Copies the given path asynchronously.
  copy: (sourcePath, destinationPath, done) ->
    mkdirp path.dirname(destinationPath), (error) ->
      if error?
        done?(error)
        return

      sourceStream = fs.createReadStream(sourcePath)
      sourceStream.on 'error', (error) ->
        done?(error)
        done = null

      destinationStream = fs.createWriteStream(destinationPath)
      destinationStream.on 'error', (error) ->
        done?(error)
        done = null
      destinationStream.on 'close', ->
        done?()
        done = null

      sourceStream.pipe(destinationStream)

  # Public: Copies the given path recursively and synchronously.
  copySync: (sourcePath, destinationPath) ->
    # We need to save the sources before creaing the new directory to avoid
    # infinitely creating copies of the directory when copying inside itself
    sources = fs.readdirSync(sourcePath)
    mkdirp.sync(destinationPath)
    for source in sources
      sourceFilePath = path.join(sourcePath, source)
      destinationFilePath = path.join(destinationPath, source)

      if fsPlus.isDirectorySync(sourceFilePath)
        fsPlus.copySync(sourceFilePath, destinationFilePath)
      else
        fsPlus.copyFileSync(sourceFilePath, destinationFilePath)

  # Public: Copies the given path synchronously, buffering reads and writes to
  # keep memory footprint to a minimum. If the destination directory doesn't
  # exist, it creates it.
  #
  # * sourceFilePath - A {String} representing the file path you want to copy.
  # * destinationFilePath - A {String} representing the file path where the file will be copied.
  # * bufferSize - An {Integer} representing the size in bytes of the buffer
  #   when reading from and writing to disk. The default is 16KB.
  copyFileSync: (sourceFilePath, destinationFilePath, bufferSize=16 * 1024) ->
    mkdirp.sync(path.dirname(destinationFilePath))

    readFd = null
    writeFd = null
    try
      readFd = fs.openSync(sourceFilePath, 'r')
      writeFd = fs.openSync(destinationFilePath, 'w')
      bytesRead = 1
      position = 0
      while bytesRead > 0
        buffer = new Buffer(bufferSize)
        bytesRead = fs.readSync(readFd, buffer, 0, buffer.length, position)
        fs.writeSync(writeFd, buffer, 0, bytesRead, position)
        position += bytesRead
    finally
      fs.closeSync(readFd) if readFd?
      fs.closeSync(writeFd) if writeFd?

  # Public: Create a directory at the specified path including any missing
  # parent directories synchronously.
  makeTreeSync: (directoryPath) ->
    mkdirp.sync(directoryPath) unless fsPlus.isDirectorySync(directoryPath)

  # Public: Create a directory at the specified path including any missing
  # parent directories asynchronously.
  makeTree: (directoryPath, callback) ->
    fsPlus.isDirectory directoryPath, (exists) ->
      return callback?() if exists
      mkdirp directoryPath, (error) -> callback?(error)

  # Public: Recursively walk the given path and execute the given functions
  # synchronously.
  #
  # rootPath - The {String} containing the directory to recurse into.
  # onFile - The {Function} to execute on each file, receives a single argument
  #          the absolute path.
  # onDirectory - The {Function} to execute on each directory, receives a single
  #               argument the absolute path (defaults to onFile). If this
  #               function returns a falsy value then the directory is not
  #               entered.
  traverseTreeSync: (rootPath, onFile, onDirectory=onFile) ->
    return unless fsPlus.isDirectorySync(rootPath)

    traverse = (directoryPath, onFile, onDirectory) ->
      for file in fs.readdirSync(directoryPath)
        childPath = path.join(directoryPath, file)
        stats = fs.lstatSync(childPath)
        if stats.isSymbolicLink()
          if linkStats = statSyncNoException(childPath)
            stats = linkStats
        if stats.isDirectory()
          traverse(childPath, onFile, onDirectory) if onDirectory(childPath)
        else if stats.isFile()
          onFile(childPath)

      undefined

    traverse(rootPath, onFile, onDirectory)

  # Public: Recursively walk the given path and execute the given functions
  # asynchronously.
  #
  # rootPath - The {String} containing the directory to recurse into.
  # onFile - The {Function} to execute on each file, receives a single argument
  #          the absolute path.
  # onDirectory - The {Function} to execute on each directory, receives a single
  #               argument the absolute path (defaults to onFile).
  traverseTree: (rootPath, onFile, onDirectory, onDone) ->
    fs.readdir rootPath, (error, files) ->
      if error
        onDone?()
      else
        queue = async.queue (childPath, callback) ->
          fs.stat childPath, (error, stats) ->
            if error
              callback(error)
            else if stats.isFile()
              onFile(childPath)
              callback()
            else if stats.isDirectory()
              if onDirectory(childPath)
                fs.readdir childPath, (error, files) ->
                  if error
                    callback(error)
                  else
                    for file in files
                      queue.unshift(path.join(childPath, file))
                    callback()
              else
                callback()
            else
              callback()
        queue.concurrency = 1
        queue.drain = onDone
        queue.push(path.join(rootPath, file)) for file in files

  # Public: Hashes the contents of the given file.
  #
  # pathToDigest - The {String} containing the absolute path.
  #
  # Returns a String containing the MD5 hexadecimal hash.
  md5ForPath: (pathToDigest) ->
    contents = fs.readFileSync(pathToDigest)
    require('crypto').createHash('md5').update(contents).digest('hex')

  # Public: Finds a relative path among the given array of paths.
  #
  # loadPaths - An {Array} of absolute and relative paths to search.
  # pathToResolve - The {String} containing the path to resolve.
  # extensions - An {Array} of extensions to pass to {resolveExtensions} in
  #              which case pathToResolve should not contain an extension
  #              (optional).
  #
  # Returns the absolute path of the file to be resolved if it's found and
  # undefined otherwise.
  resolve: (args...) ->
    extensions = args.pop() if _.isArray(_.last(args))
    pathToResolve = args.pop()?.toString()
    loadPaths = args

    return undefined unless pathToResolve

    if fsPlus.isAbsolute(pathToResolve)
      if extensions and resolvedPath = fsPlus.resolveExtension(pathToResolve, extensions)
        return resolvedPath
      else
        return pathToResolve if fsPlus.existsSync(pathToResolve)

    for loadPath in loadPaths
      candidatePath = path.join(loadPath, pathToResolve)
      if extensions
        if resolvedPath = fsPlus.resolveExtension(candidatePath, extensions)
          return resolvedPath
      else
        return fsPlus.absolute(candidatePath) if fsPlus.existsSync(candidatePath)
    undefined

  # Public: Like {.resolve} but uses node's modules paths as the load paths to
  # search.
  resolveOnLoadPath: (args...) ->
    modulePaths = null
    if module.paths?
      modulePaths = module.paths
    else if process.resourcesPath
      modulePaths = [path.join(process.resourcesPath, 'app', 'node_modules')]
    else
      modulePaths = []

    loadPaths = Module.globalPaths.concat(modulePaths)
    fsPlus.resolve(loadPaths..., args...)

  # Public: Finds the first file in the given path which matches the extension
  # in the order given.
  #
  # pathToResolve - The {String} containing relative or absolute path of the
  #                 file in question without the extension or '.'.
  # extensions - The ordered {Array} of extensions to try.
  #
  # Returns the absolute path of the file if it exists with any of the given
  # extensions, otherwise it's undefined.
  resolveExtension: (pathToResolve, extensions) ->
    for extension in extensions
      if extension is ""
        return fsPlus.absolute(pathToResolve) if fsPlus.existsSync(pathToResolve)
      else
        pathWithExtension = pathToResolve + "." + extension.replace(/^\./, "")
        return fsPlus.absolute(pathWithExtension) if fsPlus.existsSync(pathWithExtension)
    undefined

  # Public: Returns true for extensions associated with compressed files.
  isCompressedExtension: (ext) ->
    return false unless ext?
    COMPRESSED_EXTENSIONS.hasOwnProperty(ext.toLowerCase())

  # Public: Returns true for extensions associated with image files.
  isImageExtension: (ext) ->
    return false unless ext?
    IMAGE_EXTENSIONS.hasOwnProperty(ext.toLowerCase())

  # Public: Returns true for extensions associated with pdf files.
  isPdfExtension: (ext) ->
    ext?.toLowerCase() is '.pdf'

  # Public: Returns true for extensions associated with binary files.
  isBinaryExtension: (ext) ->
    return false unless ext?
    BINARY_EXTENSIONS.hasOwnProperty(ext.toLowerCase())

  # Public: Returns true for files named similarily to 'README'
  isReadmePath: (readmePath) ->
    extension = path.extname(readmePath)
    base = path.basename(readmePath, extension).toLowerCase()
    base is 'readme' and (extension is '' or fsPlus.isMarkdownExtension(extension))

  # Public: Returns true for extensions associated with Markdown files.
  isMarkdownExtension: (ext) ->
    return false unless ext?
    MARKDOWN_EXTENSIONS.hasOwnProperty(ext.toLowerCase())

  # Public: Is the filesystem case insensitive?
  #
  # Returns `true` if case insensitive, `false` otherwise.
  isCaseInsensitive: ->
    unless fsPlus.caseInsensitiveFs?
      lowerCaseStat = statSyncNoException(process.execPath.toLowerCase())
      upperCaseStat = statSyncNoException(process.execPath.toUpperCase())
      if lowerCaseStat and upperCaseStat
        fsPlus.caseInsensitiveFs = lowerCaseStat.dev is upperCaseStat.dev and lowerCaseStat.ino is upperCaseStat.ino
      else
        fsPlus.caseInsensitiveFs = false

    fsPlus.caseInsensitiveFs

  # Public: Is the filesystem case sensitive?
  #
  # Returns `true` if case sensitive, `false` otherwise.
  isCaseSensitive: -> not fsPlus.isCaseInsensitive()

  # Public: Calls `fs.statSync`, catching all exceptions raised. This
  # method calls `fs.statSyncNoException` when provided by the underlying
  # `fs` module (Electron < 3.0).
  #
  # Returns `fs.Stats` if the file exists, `false` otherwise.
  statSyncNoException: (args...) ->
    statSyncNoException(args...)

  # Public: Calls `fs.lstatSync`, catching all exceptions raised.  This
  # method calls `fs.lstatSyncNoException` when provided by the underlying
  # `fs` module (Electron < 3.0).
  #
  # Returns `fs.Stats` if the file exists, `false` otherwise.
  lstatSyncNoException: (args...) ->
    lstatSyncNoException(args...)

# Built-in [l]statSyncNoException methods are only provided in Electron releases
# before 3.0.  We delay the version check until first request so that Electron
# application snapshots can be generated successfully.
isElectron2OrLower = null
checkIfElectron2OrLower = ->
  if isElectron2OrLower is null
    isElectron2OrLower =
      process.versions.electron &&
      parseInt(process.versions.electron.split('.')[0]) <= 2
  return isElectron2OrLower

statSyncNoException = (args...) ->
  if fs.statSyncNoException and checkIfElectron2OrLower()
    fs.statSyncNoException(args...)
  else
    try
      fs.statSync(args...)
    catch error
      false

lstatSyncNoException = (args...) ->
  if fs.lstatSyncNoException and checkIfElectron2OrLower()
    fs.lstatSyncNoException(args...)
  else
    try
      fs.lstatSync(args...)
    catch error
      false

BINARY_EXTENSIONS =
  '.ds_store': true
  '.a':        true
  '.exe':      true
  '.o':        true
  '.pyc':      true
  '.pyo':      true
  '.so':       true
  '.woff':     true

COMPRESSED_EXTENSIONS =
  '.bz2':  true
  '.egg':  true
  '.epub': true
  '.gem':  true
  '.gz':   true
  '.jar':  true
  '.lz':   true
  '.lzma': true
  '.lzo':  true
  '.rar':  true
  '.tar':  true
  '.tgz':  true
  '.war':  true
  '.whl':  true
  '.xpi':  true
  '.xz':   true
  '.z':    true
  '.zip':  true

IMAGE_EXTENSIONS =
  '.gif':  true
  '.ico':  true
  '.jpeg': true
  '.jpg':  true
  '.png':  true
  '.tif':  true
  '.tiff': true
  '.webp': true

MARKDOWN_EXTENSIONS =
  '.markdown': true
  '.md':       true
  '.mdown':    true
  '.mkd':      true
  '.mkdown':   true
  '.rmd':      true
  '.ron':      true

isPathValid = (pathToCheck) ->
  pathToCheck? and typeof pathToCheck is 'string' and pathToCheck.length > 0

isMoveTargetValid = (source, target, callback) ->
  fs.stat source, (oldErr, oldStat) ->
    if oldErr
      callback(oldErr)
      return

    fs.stat target, (newErr, newStat) ->
      if newErr and newErr.code is 'ENOENT'
        callback(undefined, true) # new path does not exist so it is valid
        return

      # New path exists so check if it points to the same file as the initial
      # path to see if the case of the file name is being changed on a case
      # insensitive filesystem.
      callback(undefined, source.toLowerCase() is target.toLowerCase() and
        oldStat.dev is newStat.dev and
        oldStat.ino is newStat.ino)

isMoveTargetValidSync = (source, target) ->
  oldStat = statSyncNoException(source)
  newStat = statSyncNoException(target)

  return true unless oldStat and newStat

  # New path exists so check if it points to the same file as the initial
  # path to see if the case of the file name is being changed on a case
  # insensitive filesystem.
  source.toLowerCase() is target.toLowerCase() and
    oldStat.dev is newStat.dev and
    oldStat.ino is newStat.ino

module.exports = new Proxy({}, {
  get: (target, key) ->
    fsPlus[key] ? fs[key]

  set: (target, key, value) ->
    fsPlus[key] = value
})
