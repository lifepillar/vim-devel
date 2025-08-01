vim9script

import 'libpath.vim'                                as path
import 'libtinytest.vim'                            as tt
import '../autoload/colortemplate.vim'              as colortemplate
import '../import/colortemplate/generator/vim9.vim' as vim9generator

# Helper functions {{{
const TESTDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h')
const COLDIR  = path.Join(TESTDIR, 'colors')
const DOCDIR  = path.Join(TESTDIR, 'doc')
const EXPDIR  = path.Join(TESTDIR, 'expected')

def Verify(name: string)
  var output   = path.Join(COLDIR, $'{name}.vim')
  var expected = path.Join(EXPDIR, $'{name}.vim')

  assert_true(path.Exists(output),   $'Output not found at {output}')
  assert_true(path.Exists(expected), $'Expected output not found at {expected}')

  var fail = assert_equalfile(expected, output)

  if !fail
    delete(output)
  endif
enddef

def AssertBuild(name: string)
  var template = path.Join(TESTDIR, 'templates', name .. '.colortemplate')

  execute 'split' template

  var bufnr = bufnr("%")
  var success: bool

  try
    success = colortemplate.Build(bufnr('%'), TESTDIR, '!', {backend: 'vim9'})
  finally
    execute $':{bufnr}bwipe'
  endtry

  assert_true(success, 'Template failed to build.')

  Verify(name)
enddef
# }}}

def Test_Vim9Generator_300()
  AssertBuild('test300')
enddef

def Test_Vim9Generator_301()
  AssertBuild('test301')
enddef

def Test_Vim9Generator_302()
  AssertBuild('test302')
enddef

def Test_Vim9Generator_303()
  AssertBuild('test303')
enddef

def Test_Vim9Generator_304()
  AssertBuild('test304')
enddef

def Test_Vim9Generator_305()
  AssertBuild('test305')
enddef

def Test_Vim9Generator_306()
  AssertBuild('test306')
enddef

def Test_Vim9Generator_307()
  AssertBuild('test307')
enddef

def Test_Vim9Generator_308()
  AssertBuild('test308')
enddef

def Test_Vim9Generator_309()
  AssertBuild('test309')
enddef

def Test_Vim9Generator_310()
  AssertBuild('test310')
enddef

def Test_Vim9Generator_311()
  AssertBuild('test311')
enddef

def Test_Vim9Generator_312()
  AssertBuild('test312')
enddef

def Test_Vim9Generator_313()
  AssertBuild('test313')
enddef

def Test_Vim9Generator_314()
  AssertBuild('test314')
enddef

def Test_Vim9Generator_315()
  AssertBuild('test315')
enddef

def Test_Vim9Generator_316()
  AssertBuild('test316')
enddef

def Test_Vim9Generator_317()
  AssertBuild('test317')
enddef

def Test_Vim9Generator_318()
  AssertBuild('test318')
enddef

def Test_Vim9Generator_319()
  AssertBuild('test319')
enddef

def Test_Vim9Generator_320()
  AssertBuild('test320')
enddef

def Test_Vim9Generator_321()
  AssertBuild('test321')
enddef

def Test_Vim9Generator_322()
  AssertBuild('test322')
enddef

var results = tt.Run('_Vim9Generator_')

delete(COLDIR, "d") # Delete if empty
delete(DOCDIR, "rf")
