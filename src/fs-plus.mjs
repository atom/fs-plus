import fs from 'fs';
import Module from 'module';
import path from 'path';

const _ = require('underscore-plus');
const async = require('async');
const mkdirp = require('mkdirp');
const rimraf = require('rimraf');

// Public: Useful extensions to node's built-in fs module
//
// Important, this extends Node's builtin in ['fs' module][fs], which means that you
// can do anything that you can do with Node's 'fs' module plus a few extra
// functions that we've found to be helpful.
//
// [fs]: http://nodejs.org/api/fs.html
const fsPlus = {
  __esModule: false,

  getHomeDirectory() {
    if ((process.platform === 'win32') && !process.env.HOME) {
      return process.env.USERPROFILE;
    } else {
      return process.env.HOME;
    }
  },

  // Public: Make the given path absolute by resolving it against the current
  // working directory.
  //
  // relativePath - The {String} containing the relative path. If the path is
  //                prefixed with '~', it will be expanded to the current user's
  //                home directory.
  //
  // Returns the {String} absolute path or the relative path if it's unable to
  // determine its real path.
  absolute(relativePath) {
    if (relativePath == null) { return null; }

    relativePath = fsPlus.resolveHome(relativePath);

    try {
      return fs.realpathSync(relativePath);
    } catch (e) {
      return relativePath;
    }
  },

  // Public: Normalize the given path treating a leading `~` segment as referring
  // to the home directory. This method does not query the filesystem.
  //
  // pathToNormalize - The {String} containing the abnormal path. If the path is
  //                   prefixed with '~', it will be expanded to the current
  //                   user's home directory.
  //
  // Returns a normalized path {String}.
  normalize(pathToNormalize) {
    if (pathToNormalize == null) { return null; }

    return fsPlus.resolveHome(path.normalize(pathToNormalize.toString()));
  },

  resolveHome(relativePath) {
    if (relativePath === '~') {
      return fsPlus.getHomeDirectory();
    } else if (relativePath.indexOf(`~${path.sep}`) === 0) {
      return `${fsPlus.getHomeDirectory()}${relativePath.substring(1)}`;
    }
    return relativePath;
  },

  // Public: Convert an absolute path to tilde path for Linux and macOS.
  // /Users/username/dev => ~/dev
  //
  // pathToTildify - The {String} containing the full path.
  //
  // Returns a tildified path {String}.
  tildify(pathToTildify) {
    if (process.platform === 'win32') { return pathToTildify; }

    const normalized = fsPlus.normalize(pathToTildify);
    const homeDir = fsPlus.getHomeDirectory();
    if (homeDir == null) { return pathToTildify; }

    if (normalized === homeDir) { return '~'; }
    if (!normalized.startsWith(path.join(homeDir, path.sep))) { return pathToTildify; }

    return path.join('~', path.sep, normalized.substring(homeDir.length + 1));
  },

  // Public: Get path to store application specific data.
  //
  // Returns the {String} absolute path or null if platform isn't supported
  // Mac: ~/Library/Application Support/
  // Win: %AppData%
  // Linux: /var/lib
  getAppDataDirectory() {
    switch (process.platform) {
      case 'darwin': return fsPlus.absolute(path.join('~', 'Library', 'Application Support'));
      case 'linux':  return '/var/lib';
      case 'win32':  return process.env.APPDATA;
      default: return null;
    }
  },

  // Public: Is the given path absolute?
  //
  // pathToCheck - The relative or absolute {String} path to check.
  //
  // Returns a {Boolean}, true if the path is absolute, false otherwise.
  isAbsolute(pathToCheck='') {
    if (pathToCheck == null) { pathToCheck = ''; }
    if (process.platform === 'win32') {
      if (pathToCheck[1] === ':') { return true; } // C:\ style
      if ((pathToCheck[0] === '\\') && (pathToCheck[1] === '\\')) { return true; } // \\server\share style
    } else {
      return pathToCheck[0] === '/'; // /usr style
    }

    return false;
  },

  // Public: Returns true if a file or folder at the specified path exists.
  existsSync(pathToCheck) {
    return isPathValid(pathToCheck) && (statSyncNoException(pathToCheck) !== false);
  },

  // Public: Returns true if the given path exists and is a directory.
  isDirectorySync(directoryPath) {
    if (!isPathValid(directoryPath)) {
      return false;
    }
    const stat = statSyncNoException(directoryPath)
    if (stat) {
      return stat.isDirectory();
    } else {
      return false;
    }
  },

  // Public: Asynchronously checks that the given path exists and is a directory.
  isDirectory(directoryPath, done) {
    if (!isPathValid(directoryPath)) { return done(false); }
    return fs.stat(directoryPath, function(error, stat) {
      if (error != null) {
        return done(false);
      } else {
        return done(stat.isDirectory());
      }
    });
  },

  // Public: Returns true if the specified path exists and is a file.
  isFileSync(filePath) {
    if (!isPathValid(filePath)) {
      return false;
    }
    const stat = statSyncNoException(filePath)
    if (stat) {
      return stat.isFile();
    } else {
      return false;
    }
  },

  // Public: Returns true if the specified path is a symbolic link.
  isSymbolicLinkSync(symlinkPath) {
    if (!isPathValid(symlinkPath)) {
      return false;
    }
    const stat = lstatSyncNoException(symlinkPath)
    if (stat) {
      return stat.isSymbolicLink();
    } else {
      return false;
    }
  },

  // Public: Calls back with true if the specified path is a symbolic link.
  isSymbolicLink(symlinkPath, callback) {
    if (isPathValid(symlinkPath)) {
      return fs.lstat(symlinkPath, (error, stat) => callback?.((stat != null) && stat.isSymbolicLink()));
    } else {
      return process.nextTick(() => callback?.(false));
    }
  },

  // Public: Returns true if the specified path is executable.
  isExecutableSync(pathToCheck) {
    let stat;
    if (!isPathValid(pathToCheck)) { return false; }
    if ((stat = statSyncNoException(pathToCheck))) {
      return (stat.mode & 0o777 & 1) !== 0;
    } else {
      return false;
    }
  },

  // Public: Returns the size of the specified path.
  getSizeSync(pathToCheck) {
    if (isPathValid(pathToCheck)) {
      return statSyncNoException(pathToCheck).size ?? -1
    } else {
      return -1;
    }
  },

  // Public: Returns an Array with the paths of the files and directories
  // contained within the directory path. It is not recursive.
  //
  // rootPath - The absolute {String} path to the directory to list.
  // extensions - An {Array} of extensions to filter the results by. If none are
  //              given, none are filtered (optional).
  listSync(rootPath, extensions) {
    if (!fsPlus.isDirectorySync(rootPath)) { return []; }
    let paths = fs.readdirSync(rootPath);
    if (extensions) { paths = fsPlus.filterExtensions(paths, extensions); }
    paths = paths.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
    paths = paths.map(childPath => path.join(rootPath, childPath));
    return paths;
  },

  // Public: Asynchronously lists the files and directories in the given path.
  // The listing is not recursive.
  //
  // rootPath - The absolute {String} path to the directory to list.
  // extensions - An {Array} of extensions to filter the results by. If none are
  //              given, none are filtered (optional).
  // callback - The {Function} to call.
  list(rootPath, ...rest) {
    let extensions;
    if (rest.length > 1) { extensions = rest.shift(); }
    const done = rest.shift();
    return fs.readdir(rootPath, (error, paths) => {
      if (error != null) {
        return done(error);
      } else {
        if (extensions) { paths = fsPlus.filterExtensions(paths, extensions); }
        paths = paths.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
        paths = paths.map(childPath => path.join(rootPath, childPath));
        return done(null, paths);
      }
    });
  },

  // Returns only the paths which end with one of the given extensions.
  filterExtensions(paths, extensions) {
    extensions = extensions.map( (ext) => {
      if (ext === '') {
        return ext;
      } else {
        return '.' + ext.replace(/^\./, '');
      }
    });
    return paths.filter(pathToCheck => _.include(extensions, path.extname(pathToCheck)));
  },

  // Public: Get all paths under the given path.
  //
  // rootPath - The {String} path to start at.
  //
  // Return an {Array} of {String}s under the given path.
  listTreeSync(rootPath) {
    const paths = [];
    const onPath = (childPath) => {
      paths.push(childPath);
      return true;
    };
    fsPlus.traverseTreeSync(rootPath, onPath, onPath);
    return paths;
  },

  // Public: Moves the source file or directory to the target asynchronously.
  move(source, target, callback) {
    return isMoveTargetValid(source, target, (isMoveTargetValidErr, isTargetValid) => {
      if (isMoveTargetValidErr) {
        callback(isMoveTargetValidErr);
        return;
      }

      if (!isTargetValid) {
        const error = new Error(`'${target}' already exists.`);
        error.code = 'EEXIST';
        callback(error);
        return;
      }

      const targetParentPath = path.dirname(target);
      return fs.exists(targetParentPath, (targetParentExists) => {
        if (targetParentExists) {
          fs.rename(source, target, callback);
          return;
        }

        return fsPlus.makeTree(targetParentPath, (makeTreeErr) => {
          if (makeTreeErr) {
            callback(makeTreeErr);
            return;
          }

          fs.rename(source, target, callback);
        });
      });
    });
  },

  // Public: Moves the source file or directory to the target synchronously.
  moveSync(source, target) {
    if (!isMoveTargetValidSync(source, target)) {
      const error = new Error(`'${target}' already exists.`);
      error.code = 'EEXIST';
      throw error;
    }

    const targetParentPath = path.dirname(target);
    if (!fs.existsSync(targetParentPath)) { fsPlus.makeTreeSync(targetParentPath); }
    fs.renameSync(source, target);
  },

  // Public: Removes the file or directory at the given path synchronously.
  removeSync(pathToRemove) {
    return rimraf.sync(pathToRemove);
  },

  // Public: Removes the file or directory at the given path asynchronously.
  remove(pathToRemove, callback) {
    return rimraf(pathToRemove, callback);
  },

  // Public: Open, write, flush, and close a file, writing the given content
  // synchronously.
  //
  // It also creates the necessary parent directories.
  writeFileSync(filePath, content, options) {
    mkdirp.sync(path.dirname(filePath));
    fs.writeFileSync(filePath, content, options);
  },

  // Public: Open, write, flush, and close a file, writing the given content
  // asynchronously.
  //
  // It also creates the necessary parent directories.
  writeFile(filePath, content, options, callback) {
    callback = _.last(arguments);
    mkdirp(path.dirname(filePath), (error) => {
      if (error != null) {
        callback?.(error)
      } else {
        fs.writeFile(filePath, content, options, callback);
      }
    });
  },

  // Public: Copies the given path asynchronously.
  copy(sourcePath, destinationPath, done) {
    mkdirp(path.dirname(destinationPath), (error) => {
      if (error != null) {
        done?.(error);
        return;
      }

      const sourceStream = fs.createReadStream(sourcePath);
      sourceStream.on('error', (error) => {
        done?.(error);
        return done = null;
      });

      const destinationStream = fs.createWriteStream(destinationPath);
      destinationStream.on('error', (error) => {
        done?.(error);
        return done = null;
      });
      destinationStream.on('close', () => {
        done?.()
        return done = null;
      });

      return sourceStream.pipe(destinationStream);
    });
  },

  // Public: Copies the given path recursively and synchronously.
  copySync(sourcePath, destinationPath) {
    // We need to save the sources before creaing the new directory to avoid
    // infinitely creating copies of the directory when copying inside itself
    const sources = fs.readdirSync(sourcePath);
    mkdirp.sync(destinationPath);
      for (let source of sources) {
        const sourceFilePath = path.join(sourcePath, source);
        const destinationFilePath = path.join(destinationPath, source);

        if (fsPlus.isDirectorySync(sourceFilePath)) {
         fsPlus.copySync(sourceFilePath, destinationFilePath);
        } else {
         fsPlus.copyFileSync(sourceFilePath, destinationFilePath);
        }
      }
  },

  // Public: Copies the given path synchronously, buffering reads and writes to
  // keep memory footprint to a minimum. If the destination directory doesn't
  // exist, it creates it.
  //
  // * sourceFilePath - A {String} representing the file path you want to copy.
  // * destinationFilePath - A {String} representing the file path where the file will be copied.
  // * bufferSize - An {Integer} representing the size in bytes of the buffer
  //   when reading from and writing to disk. The default is 16KB.
  copyFileSync(sourceFilePath, destinationFilePath, bufferSize) {
    if (bufferSize == null) { bufferSize = 16 * 1024; }
    mkdirp.sync(path.dirname(destinationFilePath));

    let readFd = null;
    let writeFd = null;
    try {
      readFd = fs.openSync(sourceFilePath, 'r');
      writeFd = fs.openSync(destinationFilePath, 'w');
      let bytesRead = 1;
      let position = 0;
      while (bytesRead > 0) {
        const buffer = new Buffer(bufferSize);
        bytesRead = fs.readSync(readFd, buffer, 0, buffer.length, position);
        fs.writeSync(writeFd, buffer, 0, bytesRead, position);
        position += bytesRead;
      }
    } finally {
      if (readFd != null) { fs.closeSync(readFd); }
      if (writeFd != null) { fs.closeSync(writeFd); }
    }
  },

  // Public: Create a directory at the specified path including any missing
  // parent directories synchronously.
  makeTreeSync(directoryPath) {
    if (!fsPlus.isDirectorySync(directoryPath)) { mkdirp.sync(directoryPath); }
  },

  // Public: Create a directory at the specified path including any missing
  // parent directories asynchronously.
  makeTree(directoryPath, callback) {
    fsPlus.isDirectory(directoryPath, (exists) => {
      if (exists) { return callback?.(); }
      mkdirp(directoryPath, error => callback?.(error));
    });
  },

  // Public: Recursively walk the given path and execute the given functions
  // synchronously.
  //
  // rootPath - The {String} containing the directory to recurse into.
  // onFile - The {Function} to execute on each file, receives a single argument
  //          the absolute path.
  // onDirectory - The {Function} to execute on each directory, receives a single
  //               argument the absolute path (defaults to onFile). If this
  //               function returns a falsy value then the directory is not
  //               entered.
  traverseTreeSync(rootPath, onFile, onDirectory) {
    if (onDirectory == null) { onDirectory = onFile; }
    if (!fsPlus.isDirectorySync(rootPath)) { return; }

    const traverse = function(directoryPath, onFile, onDirectory) {
      for (let file of fs.readdirSync(directoryPath)) {
        const childPath = path.join(directoryPath, file);
        let stats = fs.lstatSync(childPath);
        if (stats.isSymbolicLink()) {
          const linkStats = statSyncNoException(childPath)
          if (linkStats) {
            stats = linkStats;
          }
        }
        if (stats.isDirectory()) {
          if (onDirectory(childPath)) { traverse(childPath, onFile, onDirectory); }
        } else if (stats.isFile()) {
          onFile(childPath);
        }
      }

      return undefined;
    };

    return traverse(rootPath, onFile, onDirectory);
  },

  // Public: Recursively walk the given path and execute the given functions
  // asynchronously.
  //
  // rootPath - The {String} containing the directory to recurse into.
  // onFile - The {Function} to execute on each file, receives a single argument
  //          the absolute path.
  // onDirectory - The {Function} to execute on each directory, receives a single
  //               argument the absolute path (defaults to onFile).
  traverseTree(rootPath, onFile, onDirectory, onDone) {
    return fs.readdir(rootPath, (error, files) => {
      if (error) {
        return onDone?.()
      } else {
        let queue = async.queue((childPath, callback) =>
          fs.stat(childPath, (error, stats) => {
            if (error) {
              return callback(error);
            } else if (stats.isFile()) {
              onFile(childPath);
              return callback();
            } else if (stats.isDirectory()) {
              if (onDirectory(childPath)) {
                return fs.readdir(childPath, (error, files) => {
                  if (error) {
                    return callback(error);
                  } else {
                    for (let file of files) {
                      queue.unshift(path.join(childPath, file));
                    }
                    return callback();
                  }
                });
              } else {
                return callback();
              }
            } else {
              return callback();
            }
          })
        );
        queue.concurrency = 1;
        queue.drain = onDone;
        for (let file of files) {
          queue.push(path.join(rootPath, file));
        }
      }
    });
  },

  // Public: Hashes the contents of the given file.
  //
  // pathToDigest - The {String} containing the absolute path.
  //
  // Returns a String containing the MD5 hexadecimal hash.
  md5ForPath(pathToDigest) {
    const contents = fs.readFileSync(pathToDigest);
    return require('crypto').createHash('md5').update(contents).digest('hex');
  },

  // Public: Finds a relative path among the given array of paths.
  //
  // loadPaths - An {Array} of absolute and relative paths to search.
  // pathToResolve - The {String} containing the path to resolve.
  // extensions - An {Array} of extensions to pass to {resolveExtensions} in
  //              which case pathToResolve should not contain an extension
  //              (optional).
  //
  // Returns the absolute path of the file to be resolved if it's found and
  // undefined otherwise.
  resolve(...args) {
    let extensions;
    if (_.isArray(_.last(args))) { extensions = args.pop(); }
    const pathToResolve = args.pop()?.toString();
    const loadPaths = args;

    if (!pathToResolve) { return undefined; }

    let resolvedPath;
    if (fsPlus.isAbsolute(pathToResolve)) {
      if (extensions && (resolvedPath = fsPlus.resolveExtension(pathToResolve, extensions))) {
        return resolvedPath;
      } else {
        if (fsPlus.existsSync(pathToResolve)) { return pathToResolve; }
      }
    }

    for (let loadPath of Array.from(loadPaths)) {
      const candidatePath = path.join(loadPath, pathToResolve);
      if (extensions) {
        resolvedPath = fsPlus.resolveExtension(candidatePath, extensions)
        if (resolvedPath) {
          return resolvedPath;
        }
      } else {
        if (fsPlus.existsSync(candidatePath)) { return fsPlus.absolute(candidatePath); }
      }
    }
    return undefined;
  },

  // Public: Like {.resolve} but uses node's modules paths as the load paths to
  // search.
  resolveOnLoadPath(...args) {
    let modulePaths = null;
    if (module.paths != null) {
      modulePaths = module.paths;
    } else if (process.resourcesPath) {
      modulePaths = [path.join(process.resourcesPath, 'app', 'node_modules')];
    } else {
      modulePaths = [];
    }

    const loadPaths = Module.globalPaths.concat(modulePaths);
    return fsPlus.resolve(...loadPaths, ...args);
  },

  // Public: Finds the first file in the given path which matches the extension
  // in the order given.
  //
  // pathToResolve - The {String} containing relative or absolute path of the
  //                 file in question without the extension or '.'.
  // extensions - The ordered {Array} of extensions to try.
  //
  // Returns the absolute path of the file if it exists with any of the given
  // extensions, otherwise it's undefined.
  resolveExtension(pathToResolve, extensions) {
    for (let extension of Array.from(extensions)) {
      if (extension === "") {
        if (fsPlus.existsSync(pathToResolve)) { return fsPlus.absolute(pathToResolve); }
      } else {
        const pathWithExtension = pathToResolve + "." + extension.replace(/^\./, "");
        if (fsPlus.existsSync(pathWithExtension)) { return fsPlus.absolute(pathWithExtension); }
      }
    }
    return undefined;
  },

  // Public: Returns true for extensions associated with compressed files.
  isCompressedExtension(ext) {
    if (ext == null) { return false; }
    return COMPRESSED_EXTENSIONS.hasOwnProperty(ext.toLowerCase());
  },

  // Public: Returns true for extensions associated with image files.
  isImageExtension(ext) {
    if (ext == null) { return false; }
    return IMAGE_EXTENSIONS.hasOwnProperty(ext.toLowerCase());
  },

  // Public: Returns true for extensions associated with pdf files.
  isPdfExtension(ext) {
    return ext?.toLowerCase() === '.pdf';
  },

  // Public: Returns true for extensions associated with binary files.
  isBinaryExtension(ext) {
    if (ext == null) { return false; }
    return BINARY_EXTENSIONS.hasOwnProperty(ext.toLowerCase());
  },

  // Public: Returns true for files named similarily to 'README'
  isReadmePath(readmePath) {
    const extension = path.extname(readmePath);
    const base = path.basename(readmePath, extension).toLowerCase();
    return (base === 'readme') && ((extension === '') || fsPlus.isMarkdownExtension(extension));
  },

  // Public: Returns true for extensions associated with Markdown files.
  isMarkdownExtension(ext) {
    if (ext == null) { return false; }
    return MARKDOWN_EXTENSIONS.hasOwnProperty(ext.toLowerCase());
  },

  // Public: Is the filesystem case insensitive?
  //
  // Returns `true` if case insensitive, `false` otherwise.
  isCaseInsensitive() {
    if (fsPlus.caseInsensitiveFs == null) {
      const lowerCaseStat = statSyncNoException(process.execPath.toLowerCase());
      const upperCaseStat = statSyncNoException(process.execPath.toUpperCase());
      if (lowerCaseStat && upperCaseStat) {
        fsPlus.caseInsensitiveFs = (lowerCaseStat.dev === upperCaseStat.dev) && (lowerCaseStat.ino === upperCaseStat.ino);
      } else {
        fsPlus.caseInsensitiveFs = false;
      }
    }

    return fsPlus.caseInsensitiveFs;
  },

  // Public: Is the filesystem case sensitive?
  //
  // Returns `true` if case sensitive, `false` otherwise.
  isCaseSensitive() { return !fsPlus.isCaseInsensitive(); },

  // Public: Calls `fs.statSync`, catching all exceptions raised. This
  // method calls `fs.statSyncNoException` when provided by the underlying
  // `fs` module (Electron < 3.0).
  //
  // Returns `fs.Stats` if the file exists, `false` otherwise.
  statSyncNoException(...args) {
    return statSyncNoException(...args);
  },

  // Public: Calls `fs.lstatSync`, catching all exceptions raised.  This
  // method calls `fs.lstatSyncNoException` when provided by the underlying
  // `fs` module (Electron < 3.0).
  //
  // Returns `fs.Stats` if the file exists, `false` otherwise.
  lstatSyncNoException(...args) {
    return lstatSyncNoException(...args);
  }
};

// Built-in [l]statSyncNoException methods are only provided in Electron releases
// before 3.0.  We delay the version check until first request so that Electron
// application snapshots can be generated successfully.
let isElectron2OrLower = null;
const checkIfElectron2OrLower = function() {
  if (isElectron2OrLower === null) {
    isElectron2OrLower =
      process.versions.electron &&
      (parseInt(process.versions.electron.split('.')[0]) <= 2);
  }
  return isElectron2OrLower;
};

let statSyncNoException = function(...args) {
  if (fs.statSyncNoException && checkIfElectron2OrLower()) {
    return fs.statSyncNoException(...args);
  } else {
    try {
      return fs.statSync(...args);
    } catch (error) {
      return false;
    }
  }
};

let lstatSyncNoException = function(...args) {
  if (fs.lstatSyncNoException && checkIfElectron2OrLower()) {
    return fs.lstatSyncNoException(...args);
  } else {
    try {
      return fs.lstatSync(...args);
    } catch (error) {
      return false;
    }
  }
};

const BINARY_EXTENSIONS = {
  '.ds_store': true,
  '.a':        true,
  '.exe':      true,
  '.o':        true,
  '.pyc':      true,
  '.pyo':      true,
  '.so':       true,
  '.woff':     true
};

const COMPRESSED_EXTENSIONS = {
  '.bz2':  true,
  '.egg':  true,
  '.epub': true,
  '.gem':  true,
  '.gz':   true,
  '.jar':  true,
  '.lz':   true,
  '.lzma': true,
  '.lzo':  true,
  '.rar':  true,
  '.tar':  true,
  '.tgz':  true,
  '.war':  true,
  '.whl':  true,
  '.xpi':  true,
  '.xz':   true,
  '.z':    true,
  '.zip':  true
};

const IMAGE_EXTENSIONS = {
  '.gif':  true,
  '.ico':  true,
  '.jpeg': true,
  '.jpg':  true,
  '.png':  true,
  '.tif':  true,
  '.tiff': true,
  '.webp': true
};

const MARKDOWN_EXTENSIONS = {
  '.markdown': true,
  '.md':       true,
  '.mdown':    true,
  '.mkd':      true,
  '.mkdown':   true,
  '.rmd':      true,
  '.ron':      true
};

let isPathValid = function(pathToCheck) {
  return (pathToCheck != null) && (typeof pathToCheck === 'string') && (pathToCheck.length > 0);
}

let isMoveTargetValid = function(source, target, callback) {
  return fs.stat(source, (oldErr, oldStat) => {
    if (oldErr) {
      callback(oldErr);
      return;
    }

    return fs.stat(target, (newErr, newStat) => {
      if (newErr && (newErr.code === 'ENOENT')) {
        callback(undefined, true); // new path does not exist so it is valid
        return;
      }

      // New path exists so check if it points to the same file as the initial
      // path to see if the case of the file name is being changed on a case
      // insensitive filesystem.
      return callback(undefined, (source.toLowerCase() === target.toLowerCase()) &&
          (oldStat.dev === newStat.dev) &&
          (oldStat.ino === newStat.ino));
    });
  });
}

let isMoveTargetValidSync = function(source, target) {
  const oldStat = statSyncNoException(source);
  const newStat = statSyncNoException(target);

  if (!oldStat || !newStat) { return true; }

  // New path exists so check if it points to the same file as the initial
  // path to see if the case of the file name is being changed on a case
  // insensitive filesystem.
  return (source.toLowerCase() === target.toLowerCase()) &&
    (oldStat.dev === newStat.dev) &&
    (oldStat.ino === newStat.ino);
};

module.exports = new Proxy({}, {
  get(target, key) {
    if (fsPlus.hasOwnProperty(key)) {
      return fsPlus[key];
    } else {
      return fs[key];
    }
  },

  set(target, key, value) {
    return fsPlus[key] = value;
  }
});
