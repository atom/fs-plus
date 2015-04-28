global.waitsForPromise = (args...) ->
  if args.length > 1
    {shouldReject} = args[0]
  else
    shouldReject = false
  fn = args[args.length - 1]

  promiseFinished = false

  process.nextTick ->
    promise = fn()
    if shouldReject
      promise.catch ->
        promiseFinished = true
      promise.then ->
        jasmine.getEnv().currentSpec.fail("Expected promise to be rejected, but it was resolved")
        promiseFinished = true
    else
      promise.then -> promiseFinished = true
      promise.catch (error) ->
        jasmine.getEnv().currentSpec.fail("Expected promise to be resolved, but it was rejected with #{jasmine.pp(error)}")
        promiseFinished = true

  global.waitsFor "promise to complete", -> promiseFinished
