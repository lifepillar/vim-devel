vim9script

import 'librelalg.vim'      as ra
import '../colorscheme.vim' as colorscheme
import '../version.vim'     as version

const KEY_NOT_FOUND   = ra.KEY_NOT_FOUND
const AntiEquiJoin    = ra.AntiEquiJoin
const DictTransform   = ra.DictTransform
const Filter          = ra.Filter
const Intersect       = ra.Intersect
const PartitionBy     = ra.PartitionBy
const Project         = ra.Project
const Query           = ra.Query
const Select          = ra.Select
const SemiJoin        = ra.SemiJoin
const Sort            = ra.Sort
const SortBy          = ra.SortBy
const Table           = ra.Table
const Transform       = ra.Transform
const Union           = ra.Union
type  Tuple           = ra.Tuple

type  Colorscheme = colorscheme.Colorscheme
type  Database    = colorscheme.Database
const VERSION     = version.VERSION

export def In(v: any, items: list<any>): bool
  return index(items, v) != -1
enddef

export def CompareDistinct(s1: string, s2: string): number
  return s1 < s2 ? -1 : 1
enddef

export def CompareByHiGroupName(t: dict<any>, u: dict<any>): number
  if t.HiGroup == u.HiGroup
    return 0
  elseif t.HiGroup == 'Normal'
    return -1
  elseif u.HiGroup == 'Normal'
    return 1
  endif

  return CompareDistinct(t.HiGroup, u.HiGroup)
enddef

export def BestCtermEnvironment(environments: list<string>): string
  for env in ['256', '88', '16', '8']
    if env->In(environments)
      return env
    endif
  endfor
  return ''
enddef

# Return a function that transforms a BaseGroup tuple into a dictionary of
# highlight group attributes. For instance:
#
# {HiGroup: 'Normal', guifg: '#ffffff', guibg: '#000000', gui: 'NONE'}
#
# Which attributes are included depends on the environment.
def MakeInstantiator(db: Database, environment: string, best_cterm = ''): func(Tuple): Tuple
  # Get the valid attributes for the given environment
  # E.g., {guifg: 'Fg',  guibg: 'Bg', guisp: 'Special', gui: 'Style'}
  var attributes = db.Attribute
    ->Select((t) => t.Environment == environment)
    ->DictTransform((t) => {
      return {[t.AttrKey]: t.AttrType}
    }, true)

  # Get the number of colors supported by the environment
  var numColors: number

  if empty(best_cterm)
    numColors = db.Environment.Lookup(
      ['Environment'], [environment]
    ).NumColors
  else
    numColors = str2nr(best_cterm)
  endif

  # Determine the color attribute to use for cterm colors
  var ctermAttr = (numColors > 16 ? 'Base256' : 'Base16')

  return (t: Tuple): Tuple => {
    var u: Tuple = {HiGroup: t.HiGroup}

    for [attr_key, attr_type] in items(attributes)
      # Determine the color value to use. Note that depends on the attribute: it
      # cannot be inferred from the environment, in general. For instance, cterm
      # attributes may be generated for the 'gui' environment, too.
      var colorAttr = attr_key[0] == 'g' ? 'GUI' : ctermAttr

      if attr_type == 'Fg' || attr_type == 'Bg' || attr_type == 'Special'

        u[attr_key] = db.Color.Lookup(['Name'], [t[attr_type]])[colorAttr]
      else
        u[attr_key] = t[attr_type]
      endif
    endfor

    return u
  }
enddef

def ApplyFixForIssue15(t: Tuple): Tuple
  # See https://github.com/lifepillar/vim-colortemplate/issues/15
  if get(t, 'guifg', '') == 'NONE' && get(t, 'guibg', '') == 'NONE'
    if !t->has_key('ctermfg')
      t.ctermfg = 'NONE'
    endif

    if !t->has_key('ctermbg')
      t.ctermbg = 'NONE'
    endif
  endif

  return t
enddef

export interface IGenerator
  def Generate(): list<string>
endinterface

export class Generator implements IGenerator
  var theme:          Colorscheme
  var language:       string
  var best_cterm:     string
  var shiftwidth:     number
  var comment_symbol: string
  var let_keyword:    string
  var const_keyword:  string
  var var_prefix:     string
  var indent:         number
  var space:          string
  var discriminatorNames: list<string> = []
  var needs_t_Co = false
  var needs_tgc  = false

  var _cache: dict<any> = {}

  def new(this.theme, language: string)
    this.Init(language)
  enddef

  def Init(language: string)
    this.language   = language
    this.best_cterm = BestCtermEnvironment(this.theme.environments)
    this.shiftwidth = this.theme.options.shiftwidth
    this.SetLanguage()
    this.ResetIndent()
  enddef

  def SetLanguage()
    if this.language == 'vim9'
      this.comment_symbol = '# '
      this.let_keyword    = ''
      this.const_keyword  = 'const '
      this.var_prefix     = ''
    elseif this.language == 'vim'
      this.comment_symbol = '" '
      this.let_keyword    = 'let '
      this.const_keyword  = 'let '
      this.var_prefix     = 's:'
    else
      throw $'Unsupported language: {this.language}.'
    endif
  enddef

  def ResetIndent()
    this.indent = 0
    this.space  = ''
  enddef

  def Indent()
    this.indent += this.shiftwidth
    this.space = repeat(' ', this.indent)
  enddef

  def Deindent()
    this.indent -= this.shiftwidth
    this.space = repeat(' ', this.indent)
  enddef

  def Generate(): list<string>
    var header: list<string> = this.language == 'vim9'
      ? ['vim9script', '']
      : []
    var output: list<string> = []

    this.ResetIndent()

    header += this.EmitHeader()
    output += this.EmitCommonLinkedGroups()
    output += this.Emit('dark')
    output += this.Emit('light')
    output += this.EmitFooter()

    var special_vars = this.EmitSpecialVars() # t_Co and tgc

    return header + special_vars + output
  enddef

  def Add(output: list<string>, text: string)
    output->add(this.space .. text)
  enddef

  def AddMeta(output: list<string>, template: string, value: string)
    if empty(value)
      return
    endif

    output->add(this.comment_symbol .. printf(template, value))
  enddef

  def AddMultivaluedMeta(output: list<string>, template: string, items: list<string>)
    if empty(items)
      return
    endif

    output->this.AddMeta(template, items[0])

    var n = len(items)
    var space = repeat(' ', 14)
    var i = 1

    while i < n
      output->add(this.comment_symbol .. printf('%s%s', space, items[i]))
      ++i
    endwhile
  enddef

  def DiscriminatorToString(t: Tuple): string
    return $'{this.space}{this.const_keyword}{this.var_prefix}{t.DiscrName} = {t.Definition}'
  enddef

  def LinkedGroupToString(t: Tuple): string
    if empty(t.TargetGroup)
      return null_string  # Skip definition
    endif

    return $"{this.space}hi! link {t.HiGroup} {t.TargetGroup}"
  enddef

  def BaseGroupToString(t: Tuple): string
    var attributes: list<string> = []

    for attr in ['guifg', 'guibg', 'guisp', 'gui', 'ctermfg', 'ctermbg', 'cterm', 'term']
      var value = get(t, attr, '')

      if !empty(value)
        attributes->add($'{attr}={value}')
      endif
    endfor

    # The following attributes are generated only if their value is not NONE
    for attr in ['ctermul', 'start', 'stop', 'font']
      var value = get(t, attr, '')

      if !empty(value) && value != 'NONE'
        attributes->add($'{attr}={value}')
      endif
    endfor

    if empty(attributes)
      return null_string  # Skip definition
    endif

    return $"{this.space}hi {t.HiGroup} {join(attributes, ' ')}"
  enddef

  def EmitHeader(): list<string>
    var theme = this.theme
    var output: list<string> = []

    var sa = len(theme.authors) > 1     ? 's:' : ': '
    var sm = len(theme.maintainers) > 1 ? 's:' : ': '
    var su = len(theme.urls) > 1        ? 's:' : ': '

    output->this.AddMeta('Name:         %s', theme.fullname)
    output->this.AddMeta('Version:      %s', theme.version)
    output->this.AddMultivaluedMeta('Description:  %s', theme.description)
    output->this.AddMultivaluedMeta($'Author{sa}      %s', theme.authors)
    output->this.AddMultivaluedMeta($'Maintainer{sm}  %s', theme.maintainers)
    output->this.AddMultivaluedMeta($'URL{su}         %s', theme.urls)
    output->this.AddMeta('License:      %s', theme.license)

    if theme.options.timestamp
      output->this.AddMeta('Last Change:  %s', strftime(theme.options.dateformat))
    endif

    output->add('')

    if theme.options.creator
      output->this.AddMeta('Generated by Colortemplate v%s', VERSION)
      output->add('')
    endif

    if !theme.backgrounds.light
      output->add('set background=dark')
      output->add('')
    elseif !theme.backgrounds.dark
      output->add('set background=light')
      output->add('')
    endif

    output->add('hi clear')
    output->add($"{this.let_keyword}g:colors_name = '{theme.shortname}'")
    output->add('')

    if !empty(theme.verbatimtext)
      output += theme.verbatimtext
      output->add('')
    endif

    return output
  enddef

  def EmitFooter(): list<string>
    var theme = this.theme
    var output: list<string> = []

    if theme.options.palette # Write the color palette as a comment
      for background in ['dark', 'light']
        if theme.HasBackground(background)
          var db = theme.Db(background)
          var palette = db.Color
            ->Select((t) => !(empty(t.Name) || t.Name->In(['none', 'fg', 'bg', 'ul'])))
            ->SortBy('Name')

          output->add(this.comment_symbol .. 'Background: ' .. background)
          output->add(this.comment_symbol)
          output += map(split(Table(palette, {
            columns: [
              'Name',
              'GUI',
              'Base256',
              'Base256Hex',
              'Base16'
            ]
          }), "\n"), (_, v) => this.comment_symbol .. v)
          output->add('')
        endif
      endfor
    endif

    output->add(this.comment_symbol .. $'vim: et ts=8 sw={this.shiftwidth} sts={this.shiftwidth}')

    return output
  enddef

  # Emit linked group definitions common to dark and light backgrounds
  def EmitCommonLinkedGroups(): list<string>
    if !this.theme.IsLightAndDark()
      return []
    endif

    var output: list<string> = []

    output = this.theme.Db('dark').LinkedGroup->Select((t) => t.Condition == 0)
      ->Intersect(
        this.theme.Db('light').LinkedGroup->Select((t) => t.Condition == 0)
      )
    ->Sort(CompareByHiGroupName)
    ->Transform((t) => this.LinkedGroupToString(t))

    if !empty(output)
      output->add('')
    endif

    return output
  enddef

  def Emit(background: string): list<string>
    if !this.theme.HasBackground(background)
      return []
    endif

    var db = this.theme.Db(background)

    # Partition and cache highlight group definitions
    this._cache.linked = PartitionBy(db.LinkedGroup, 'Condition')
    this._cache.base   = PartitionBy(db.BaseGroup,   'Condition')

    # All non-empty discriminator names
    this.discriminatorNames = db.Discriminator
      ->Filter((t) => !empty(t.DiscrName))
      ->Project('DiscrName')
      ->SortBy('DiscrName')
      ->Transform((t) => t.DiscrName)

    var has_gui = 'gui'->In(this.theme.environments)
    var has_256 = '256'->In(this.theme.environments)
    var has_16  =  '16'->In(this.theme.environments)
    var has_8   =   '8'->In(this.theme.environments)
    var has_0   =   '0'->In(this.theme.environments)

    var start_background         = this.StartBackground(background)
    var term_colors              = this.EmitTerminalColors(db)
    var verbatim_text            = this.EmitVerbatimText(db)
    var discriminators           = this.EmitDiscriminators(db)
    var default_linked_groups    = this.EmitDefaultLinkedGroups(db)
    var default_base_groups      = this.EmitDefaultBaseGroups(db)
    var gui_definitions          = has_gui ? this.EmitGuiDefinitions(db)     : []
    var t256_definitions         = has_256 ? this.EmitBase256Definitions(db) : []
    var common_cterm_definitions = this.EmitCommonCtermDefinitions(db)
    var t16_definitions          = has_16  ? this.EmitBase16Definitions(db)  : []
    var t8_definitions           = has_8   ? this.EmitBase8Definitions(db)   : []
    var t0_definitions           = has_0   ? this.EmitBase0Definitions(db)   : []

    var must_generate_0   = has_0   && !empty(t0_definitions)
    var must_generate_8   = has_8   && (!empty(t8_definitions) || must_generate_0)
    var must_generate_16  = has_16  && (!empty(t16_definitions) || must_generate_8 || must_generate_0)
    var must_generate_256 = has_256 && (!empty(t256_definitions) || must_generate_16 || must_generate_8 || must_generate_0)
    var must_generate_gui = has_gui && !empty(gui_definitions)

    if must_generate_gui
      gui_definitions = this.StartGuiBlock() + gui_definitions + this.EndGuiBlock()
    endif

    if must_generate_256
      t256_definitions = this.StartTermBlock('256') + t256_definitions + this.EndTermBlock('256')
    endif

    if must_generate_16
      t16_definitions = this.StartTermBlock('16') + t16_definitions + this.EndTermBlock('16')
    endif

    if must_generate_8
      t8_definitions = this.StartTermBlock('8') + t8_definitions + this.EndTermBlock('8')
    endif

    if must_generate_0
      t0_definitions = this.StartTermBlock('0') + t0_definitions + this.EndTermBlock('0')
    endif

    var end_background = this.EndBackground(background)

    return start_background
      + term_colors
      + verbatim_text
      + discriminators
      + default_linked_groups
      + default_base_groups
      + gui_definitions
      + t256_definitions
      + common_cterm_definitions
      + t16_definitions
      + t8_definitions
      + t0_definitions
      + end_background
  enddef

  def StartBackground(background: string): list<string>
    var output: list<string> = []

    if this.theme.IsLightAndDark()
      output->this.Add($"if &background == '{background}'")
      this.Indent()
    endif

    return output
  enddef

  def EndBackground(background: string): list<string>
    var output: list<string> = []

    if this.theme.IsLightAndDark()
      if background == 'dark'
        output->this.Add('finish')
      endif

      this.Deindent()
      output->this.Add('endif')
      output->add('')
    endif

    return output
  enddef

  def StartGuiBlock(): list<string>
    this.needs_tgc  = true

    return [
      $"{this.space}if has('gui_running') || {this.var_prefix}tgc",
    ]
  enddef

  def EndGuiBlock(): list<string>
    return [$'{this.space}endif', '']
  enddef

  def StartTermBlock(t_Co: string): list<string>
    this.needs_t_Co = true

    if t_Co == this.best_cterm
      this.needs_tgc  = true

      return [
        $"{this.space}if {this.var_prefix}tgc || {this.var_prefix}t_Co >= {t_Co}",
      ]
    endif

    return [
      $"{this.space}if {this.var_prefix}t_Co >= {t_Co}",
    ]
  enddef

  def EndTermBlock(t_Co: string): list<string>
    var output: list<string> = []

    this.Indent()
    output->this.Add('finish')
    this.Deindent()
    output->this.Add('endif')
    output->add('')

    return output
  enddef

  def EmitTerminalColors(db: Database): list<string>
    var output: list<string> = []

    if !empty(db.termcolors)
      output->this.Add(printf(
        $'{this.let_keyword}g:terminal_ansi_colors = %s',
        mapnew(db.termcolors, (_, name) => db.Color.Lookup(['Name'], [name]).GUI)
      ))
      output->add('')
    endif

    return output
  enddef

  # Background-specific verbatim text
  def EmitVerbatimText(db: Database): list<string>
    var output: list<string> = []

    if !empty(db.verbatimtext)
      output += mapnew(
        db.verbatimtext, (_, line) => empty(line) ? line : this.space .. line
      )
      output->add('')
    endif

    return output
  enddef

  def EmitDiscriminators(db: Database): list<string>
    var output = db.Discriminator
      ->Filter((t) => !empty(t.DiscrName) && t.DiscrName != 't_Co' && t.DiscrName != 'tgc')
      ->SortBy('DiscrNum')
      ->Transform((t) => this.DiscriminatorToString(t))

    if !empty(output)
      output->add('')
    endif

    return output
  enddef

  def EmitDefaultLinkedGroups(db: Database): list<string>
    var output: list<string> = []
    var linked = this._cache.linked->get(0, []) # Default linked group definitions

    if this.theme.IsLightAndDark()
      var background       = db.background
      var other_background = background == 'dark' ? 'light' : 'dark'
      var OtherLinked      = this.theme.Db(other_background).LinkedGroup->Select((t) => t.Condition == 0)

      output += linked
        ->AntiEquiJoin(OtherLinked, {on: ['HiGroup', 'Condition']})
        ->Sort(CompareByHiGroupName)
        ->Transform((t) => this.LinkedGroupToString(t))
    else # Single background
      output += linked
        ->Sort(CompareByHiGroupName)
        ->Transform((t) => this.LinkedGroupToString(t))
    endif

    if !empty(output)
      output->add('')
    endif

    return output
  enddef

  def EmitDefaultBaseGroups(db: Database): list<string>
    var Instantiate   = MakeInstantiator(db, 'default', this.best_cterm)
    var GuiOverride   = this.MakeGuiOverride(db)
    var CtermOverride = this.MakeCtermOverride(db, this.best_cterm)
    var TermOverride  = this.MakeTermOverride(db)

    var output = this._cache.base->get(0, []) # Default definitions
      ->Sort(CompareByHiGroupName)
      ->Transform((t): string => this.BaseGroupToString(
        Instantiate(t)
        ->GuiOverride()
        ->CtermOverride()
        ->TermOverride()
      ))

    output += this.HookEndOfEnvironment(db, 'default')
    output->add('')

    return output
  enddef

  def EmitGuiDefinitions(db: Database): list<string>
    var Instantiate = MakeInstantiator(db, 'gui')
    var c = db.Condition.Lookup(
      ['Environment', 'DiscrName', 'DiscrValue'],
      ['gui',         '',           ''         ]
    )
    var output = []

    this.Indent()

    if c isnot KEY_NOT_FOUND
      # Generate linked group overrides
      output += this._cache.linked->get(c.Condition, [])
        ->Sort(CompareByHiGroupName)
        ->Transform((t) => this.LinkedGroupToString(t))

      # Base group overrides have already been merged into default definitions.
      # The exception is when a default linked group is overridden with a base
      # group: in this case, the overriding definition must be output
      # separately.
      output += this._cache.base->get(c.Condition, [])
        ->SemiJoin(this._cache.linked->get(0, []), (t, u) => t.HiGroup == u.HiGroup)
        ->Sort(CompareByHiGroupName)
        ->Transform((t) => this.BaseGroupToString(Instantiate(t)))
    endif

    # Emit discriminator-based definitions
    output += this.EmitDiscriminatorBasedDefinitions(db, 'gui')
    output += this.HookEndOfEnvironment(db, 'gui')

    this.Deindent()

    return output
  enddef

  def EmitTerminalDefinitions(db: Database, t_Co: string): list<string>
    var Instantiate = MakeInstantiator(db, t_Co)
    var c = db.Condition.Lookup(
      ['Environment', 'DiscrName', 'DiscrValue'],
      [ t_Co,         '',          ''          ]
    )
    var output = []

    this.Indent()

    var t_Co_linked = this._cache.linked->get(c->get('Condition', -1), [])
    var t_Co_base = this._cache.base->get(c->get('Condition', -1), [])

    # Generate linked group overrides
    output += t_Co_linked
      ->Sort(CompareByHiGroupName)
      ->Transform((t) => this.LinkedGroupToString(t))

    # best_cterm and '0' definitions were already merged into default
    # definitions. The exception is when the default definition is a linked
    # group and the override is a base group: in this case, the overriding
    # definition must be kept.
    if t_Co == this.best_cterm || t_Co == '0'
      output += t_Co_base
        ->SemiJoin(this._cache.linked->get(0, []), (t, u) => t.HiGroup == u.HiGroup)
        ->Sort(CompareByHiGroupName)
        ->Transform((t) => this.BaseGroupToString(Instantiate(t)))
    else
      # All default base group definitions that are not overridden must be
      # generated, too.
      output += this._cache.base->get(0, []) # Default definitions (Condition = 0)
        ->AntiEquiJoin(t_Co_base,   {on: 'HiGroup'})
        ->AntiEquiJoin(t_Co_linked, {on: 'HiGroup'})
        ->Union(t_Co_base)
        ->Sort(CompareByHiGroupName)
        ->Transform((t) => this.BaseGroupToString(Instantiate(t)))
    endif

    # Emit discriminator-based definitions
    output += this.EmitDiscriminatorBasedDefinitions(db, t_Co)
    output += this.HookEndOfEnvironment(db, t_Co)

    this.Deindent()

    return output
  enddef

  def EmitBase256Definitions(db: Database): list<string>
    return this.EmitTerminalDefinitions(db, '256')
  enddef

  def EmitCommonCtermDefinitions(db: Database): list<string>
    return [] # Not implemented yet
  enddef

  def EmitBase16Definitions(db: Database): list<string>
    return this.EmitTerminalDefinitions(db, '16')
  enddef

  def EmitBase8Definitions(db: Database): list<string>
    return this.EmitTerminalDefinitions(db, '8')
  enddef

  def EmitBase0Definitions(db: Database): list<string>
    return this.EmitTerminalDefinitions(db, '0')
  enddef

  def EmitDiscriminatorBasedDefinitions(db: Database, environment: string): list<string>
    var output: list<string> = []

    for discrName in this.discriminatorNames
      var conditions = db.Condition
        ->Select((t) => t.Environment == environment && t.DiscrName == discrName)
        ->SortBy('DiscrValue')

      if empty(conditions)
        continue
      endif

      if discrName == 't_Co'
        this.needs_t_Co = true
      endif

      if discrName == 'tgc'
        this.needs_tgc = true
      endif

      var first = true

      for condition in conditions
        var clause = 'elseif '

        if first
          clause = 'if '
          first = false
        endif

        if condition.DiscrValue == 'true'
          clause ..= $'{this.var_prefix}{discrName}'
        elseif condition.DiscrValue == 'false'
          clause ..= $'!{this.var_prefix}{discrName}'
        else
          clause ..= $'{this.var_prefix}{discrName} == {condition.DiscrValue}'
        endif

        output->this.Add(clause)

        this.Indent()

        output += this.EmitDiscriminatorValueDefinitions(db, environment, discrName, condition.DiscrValue)
        output += this.HookEndOfDiscriminatorBlock(db, environment, discrName, condition.DiscrValue)

        this.Deindent()
      endfor

      output ->this.Add('endif')
    endfor

    return output
  enddef

  def EmitDiscriminatorValueDefinitions(
      db:          Database,
      environment: string,
      discrName:   string,
      discrValue:  string
      ): list<string>
    var c = db.Condition.Lookup(
      ['Environment', 'DiscrName', 'DiscrValue'],
      [ environment,   discrName,   discrValue ]
    )

    if c is KEY_NOT_FOUND
      return []
    endif

    var Instantiate = MakeInstantiator(db, environment)
    var output: list<string> = []

    output += this._cache.linked->get(c.Condition, [])
      ->Sort(CompareByHiGroupName)
      ->Transform((t) => this.LinkedGroupToString(t))

    output += this._cache.base->get(c.Condition, [])
      ->Sort(CompareByHiGroupName)
      ->Transform((t) => this.BaseGroupToString(Instantiate(t)))

    return output
  enddef

  def EmitSpecialVars(): list<string>
    var output: list<string> = []

    if this.needs_t_Co
      var t = this.theme.dark.Discriminator.Lookup(['DiscrName'], ['t_Co'])
      output->add(this.DiscriminatorToString(t))
    endif

    if this.needs_tgc
      var t = this.theme.dark.Discriminator.Lookup(['DiscrName'], ['tgc'])
      output->add(this.DiscriminatorToString(t))
    endif

    if !empty(output)
      output->add('')
    endif

    return output
  enddef

  def HookEndOfEnvironment(db: Database, environment: string): list<string>
    return []
  enddef

  def HookEndOfDiscriminatorBlock(
      db:          Database,
      environment: string,
      discrName:   string,
      discrValue:  string
      ): list<string>
    return []
  enddef

  # Return a function that takes an instantiated BaseGroup tuple (see
  # MakeInstantiator()) and returns the same tuple updated with values coming
  # from a corresponding gui overriding definition, if present. The tuple is
  # updated in-place.
  def MakeGuiOverride(db: Database): func(Tuple): Tuple
    var c = db.Condition.Lookup(
      ['Environment', 'DiscrName', 'DiscrValue'],
      ['gui',         '',          ''          ]
    )
    var guiDefinitions = this._cache.base->get(c->get('Condition', -1), [])

    return (t: Tuple): Tuple => {
      var r = Query(guiDefinitions->Select((w) => w.HiGroup == t.HiGroup))

      if empty(r)
        return ApplyFixForIssue15(t)
      endif

      var u = r[0]

      if !empty(u.Fg)
        t.guifg = db.Color.Lookup(['Name'], [u.Fg]).GUI
      endif

      if !empty(u.Bg)
        t.guibg = db.Color.Lookup(['Name'], [u.Bg]).GUI
      endif

      if !empty(u.Special)
        t.guisp = db.Color.Lookup(['Name'], [u.Special]).GUI
      endif

      if !empty(u.Style)
        t.gui   = u.Style

        if !t->has_key('cterm')
          t.cterm = u.Style # For capable terminals when termguicolors is set
        endif
      endif

      return ApplyFixForIssue15(t)
    }
  enddef

  # Same as MakeGuiOverride(), but for cterm* attributes
  def MakeCtermOverride(db: Database, cterm: string): func(Tuple): Tuple
    var c = db.Condition.Lookup(
      ['Environment', 'DiscrName', 'DiscrValue'],
      [cterm,         '',          ''          ]
    )
    var ctermDefinitions = this._cache.base->get(c->get('Condition', -1), [])
    var cterm_attr = str2nr(cterm) > 16 ? 'Base256' : 'Base16'

    return (t: Tuple): Tuple => {
      var r = Query(ctermDefinitions->Select((w) => w.HiGroup == t.HiGroup))

      if empty(r)
        return t
      endif

      var u = r[0]

      if !empty(u.Fg)
        t.ctermfg = db.Color.Lookup(['Name'], [u.Fg])[cterm_attr]
      endif

      if !empty(u.Bg)
        t.ctermbg = db.Color.Lookup(['Name'], [u.Bg])[cterm_attr]
      endif

      if !empty(u.Special)
        t.ctermul = db.Color.Lookup(['Name'], [u.Special])[cterm_attr]
      endif

      if !empty(u.Style)
        t.cterm = u.Style
      endif

      return t
    }
  enddef

  # Same as MakeGuiOverride(), but for term* attributes
  def MakeTermOverride(db: Database): func(Tuple): Tuple
    var c = db.Condition.Lookup(
      ['Environment', 'DiscrName', 'DiscrValue'],
      ['0',           '',          ''          ]
    )
    var termDefinitions = this._cache.base->get(c->get('Condition', -1), [])

    return (t: Tuple): Tuple => {
      var r = Query(termDefinitions->Select((w) => w.HiGroup == t.HiGroup))

      if empty(r)
        return t
      endif

      if !empty(r[0].Style)
        t.term = r[0].Style
      endif

      return t
    }
  enddef

endclass
