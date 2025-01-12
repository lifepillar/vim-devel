vim9script

# Author:       Lifepillar <lifepillar@lifepillar.me>
# Maintainer:   Lifepillar <lifepillar@lifepillar.me>
# Website:      https://github.com/lifepillar/vim-devel
# License:      Vim License (see `:help license`)

if !&magic
  echomsg "LibTinyTest requires 'magic' on"
  finish
endif

# Local state {{{
export class Config
  public static var highlight = get(g:, 'libtinytest_highlight', true)
  public static var ok        = get(g:, 'libtinytest_ok',         '✔︎')
  public static var failed    = get(g:, 'libtinytest_failed',     '✘')
  public static var quiet     = get(g:, 'libtinytest_quiet',    false)
  public static var dryrun    = false

  static def Width(): number
    return max([strdisplaywidth(Config.ok), strdisplaywidth(Config.failed)])
  enddef
endclass

class BenchmarkResult
  var description:  string      # Benchmark description
  var measurements: list<float> # Measurements
  var loop:         number      # Number of iteration for each measurement
  var severity:     dict<float> # Severity thresholds
endclass

class TestResult
  var test:       string                # Test name
  var elapsed:    float                 # Test duration in milliseconds
  var errors:     list<string>          # Error messages generated by the test
  var benchmarks: list<BenchmarkResult> # Results of benchmarks run by this test

  def Ok(): bool
    return empty(this.errors)
  enddef
endclass

var vBenchmarks: list<BenchmarkResult> = []

export var done = 0
export var fail = 0
# }}}

# Private functions {{{
def FindTests(pattern: string): list<dict<string>>
  const saved_reg = getreg('t')
  const saved_regtype = getregtype('t')

  redir @t
  execute 'silent def /Test_*' .. pattern
  redir END

  const defnames = split(@t, "\n")
  var tests: list<dict<string>> = []

  for t in defnames
    if t =~ '^def <SNR>\d\+\k\+()$'
      const test = substitute(t, '^def ', '\1', '')  # E.g., '<SNR>9_Test_Foo()'
      const name = substitute(test, '^<SNR>\d\+_Test_*\(.\+\)()$', '\1', '')  # E.g., 'Foo'
      tests->add({'test': test, 'name': name})
    endif
  endfor

  setreg('t', saved_reg, saved_regtype)

  return tests
enddef

def Min2(a: float, b: float): float
  return a <= b ? a : b
enddef

def Max2(a: float, b: float): float
  return a >= b ? a : b
enddef

def Min(values: list<float>): float
  return reduce(values, (acc, x) => x < acc ? x : acc, values[0])
enddef

def Mean(values: list<float>): float
  return reduce(values, (acc, x) => acc + x, 0.0) / len(values)
enddef

def Stddev(measurements: list<float>): float
  var mean        = Mean(measurements)
  var squared_sum = reduce(measurements, (acc, x) => acc + pow(x - mean, 2), 0.0)

  return sqrt(squared_sum / (len(measurements) - 1))
enddef

def Measure(F: func(), repeat: number, loop: number): list<float>
  var measurements: list<float> = []
  var start_time:   list<any>
  var elapsed_time: float

  var i = 0

  while i < repeat
    var k = 0

    start_time = reltime()

    while k < loop
      F()
      ++k
    endwhile

    elapsed_time = reltimefloat(reltime(start_time)) / loop
    measurements->add(1000.0 * elapsed_time) # ms
    ++i
  endwhile

  return measurements
enddef

def TuneBenchmark(F: func(), threshold = 200.0): number
  # Find a number of iterations that requires more than `threshold` ms
  var i    = 1
  var loop = 1

  while true
    for j in [1, 2, 5]
      loop = i * j
      var measurements = Measure(F, 1, loop)

      if loop * measurements[0] >= threshold # ms
        return loop
      endif
    endfor

    i *= 10
  endwhile

  return loop
enddef

def Noop()
enddef

export var Setup:    func() = Noop
export var Teardown: func() = Noop

# test: the full function invocation (e.g., '<SNR>1_Test_Foobar()')
# name: the test name (e.g., 'Foobar')
def RunTest(test: string, name: string): TestResult
  var start_time = reltime()

  v:errors    = []
  vBenchmarks = []

  Setup()

  try
    execute test
  catch
    add(v:errors, $'Caught exception in {name}: {v:exception} @ {v:throwpoint}')
  endtry

  done += 1
  Teardown()

  var elapsed_time = 1000.0 * reltimefloat(reltime(start_time))

  if empty(v:errors)
    return TestResult.new(name, elapsed_time, [], vBenchmarks)
  endif

  fail += 1

  var errors = copy(v:errors)

  v:errors = []

  return TestResult.new(name, elapsed_time, errors, vBenchmarks)
enddef

def FormatBenchmarkResult(benchmark_result: BenchmarkResult): string
  var severity  = ''
  var threshold = 0.0
  var N         = len(benchmark_result.measurements)
  var best      = Min(benchmark_result.measurements)
  var stddev    = N > 1 ? '±' .. printf('%.3f', Stddev(benchmark_result.measurements)) : ''
  var mean      = Mean(benchmark_result.measurements)

  for [key, value] in items(benchmark_result.severity)
    if value < mean && value >= threshold
      severity  = key
      threshold = value
    endif
  endfor

  return printf($'%s %s: %.3fms%s (best: %.3fms) [%d run%s, %d loop%s per run]',
    severity,
    benchmark_result.description,
    mean,
    stddev,
    best,
    N,
    N != 1 ? 's' : '',
    benchmark_result.loop,
    benchmark_result.loop != 1 ? 's' : ''
  )
enddef

def FormatTestResult(test_result: TestResult, width = Config.Width()): string
  var ok = test_result.Ok()
  var symbol = ok ? Config.ok : Config.failed
  var failed = ok ? '' : ' FAILED'

  return printf($'%-{width}S %s (%.01fms)%s',
    symbol, test_result.test, test_result.elapsed, failed
  )
enddef

def FormatTestErrors(test_result: TestResult): list<string>
  if test_result.Ok()
    return []
  endif

  var errorMessages: list<string> = [
    '',
    test_result.test
  ]

  for error in test_result.errors
    if error =~# '^Caught exception'
      errorMessages->add(substitute(error, '^Caught exception\zs.*: Vim[^:]*\ze:', '', ''))
    else
      errorMessages->add(substitute(error, '^.*\zeline \d\+', '', ''))
    endif
  endfor

  return errorMessages
enddef

def FormatTestResults(test_results: list<TestResult>, elapsed_time: float): list<string>
  var output: list<string> = []
  var benchmarks_output: list<string> = []
  var succeeded = (fail == 0)

  output->add(strftime('--- %c ---'))
  output->add('')

  for test_result in test_results
    output->add(FormatTestResult(test_result))

    for benchmark_result in test_result.benchmarks
      benchmarks_output->add(FormatBenchmarkResult(benchmark_result))
    endfor
  endfor

  if !empty(benchmarks_output)
    output->add('')
    output->add('-- Benchmark Results --')
    output->add('')
    output->extend(benchmarks_output)
  endif

  output->add('')
  output->add(printf('%d test%s run in %.03fs', done, (done == 1 ? '' : 's'), elapsed_time))

  if succeeded
    output->add(Config.ok .. ' ALL TESTS PASSED!')
  else
    output->add(printf('%d test%s failed', fail, (fail == 1 ? '' : 's')))
  endif

  output->add('')

  for test_result in test_results
    output->extend(FormatTestErrors(test_result))
  endfor

  return output
enddef

def FinishTesting(test_results: list<TestResult>, elapsed_time: float)
  botright new
  setlocal
        \ buftype=nofile
        \ bufhidden=wipe
        \ nobuflisted
        \ noswapfile
        \ wrap

  append(0, FormatTestResults(test_results, elapsed_time))

  if Config.highlight
    matchadd('Identifier', Config.ok)
    matchadd('WarningMsg', Config.failed)
    matchadd('WarningMsg', '\<FAILED\>')
    matchadd('WarningMsg', '^\d\+ tests\? failed')
    matchadd('Keyword',    '^\<line \d\+')
    matchadd('Constant',   '\<Expected\>')
    matchadd('Constant',   '\<but got\>')
    matchadd('ErrorMsg',   'Caught exception')
  endif

  if fail == 0
    normal G
  else
    search('^\d\+ tests\= run in')
    normal ztjj
  endif

  nunmenu WinBar

  Setup    = Noop
  Teardown = Noop
enddef
# }}}

# Public interface {{{
export def Import(path: string)
  Config.dryrun = true
  execute 'source' path
  Config.dryrun = false
enddef

export def Round(num: float, digits: number): float
  return str2float(printf('%.0' .. digits .. 'f', num))
enddef

export def AssertApprox(
    expected: float, value: float, rtol = 0.001, atol = 0.0, msg = ''
)
  const tmin = Min2(expected - rtol * expected, expected - atol)
  const tmax = Max2(expected + rtol * expected, expected + atol)

  assert_inrange(tmin, tmax, value, msg)
enddef

export def AssertBenchmark(F: func(), description = '', opts: dict<any> = {})
  var nloop        = opts->get('loop', TuneBenchmark(F))
  var repeat       = opts->get('repeat', 1)
  var severity     = opts->get('severity', {})
  var measurements = Measure(F, repeat, nloop)

  vBenchmarks->add(BenchmarkResult.new(
    description,
    measurements,
    nloop,
    opts->get('severity', {}),
  ))
enddef

export def AssertFails(F: func(), expectedError: string, msg = '')
  try
    F()
    assert_false(true,
      'Function should have thrown an error, but succeeded' .. (empty(msg) ? '' : $'. {msg}')
    )
  catch
    assert_exception(expectedError, msg)
  endtry
enddef

export def Run(pattern: string = ''): list<TestResult>
  if Config.dryrun
    return []
  endif

  var tests:        list<dict<string>> = FindTests(pattern)
  var test_results: list<TestResult>   = []
  var start_time = reltime()

  done = 0
  fail = 0

  for test in tests
    test_results->add(RunTest(test.test, test.name))
  endfor

  var elapsed_time = reltimefloat(reltime(start_time))

  if !Config.quiet
    FinishTesting(test_results, elapsed_time)
  endif

  return test_results
enddef
# }}}

# vim: nowrap et ts=2 sw=2
