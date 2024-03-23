vim9script

# Helper functions {{{
def NotIn(v: any, items: list<any>): bool
  return indexof(items, (_, u) => u is v) == -1
enddef

def RemoveFrom(v: any, items: list<any>)
  const i = indexof(items, (_, e) => e is v)
  if i == -1
    return
  endif
  items->remove(i)
enddef
# }}}

# Effects {{{
interface IProperty
  def Get(): any
  def Set(value: any, force: bool)
  def Clear()
  def RemoveEffect(effect: any)
endinterface

class Effect
  var Fn: func()
  public var dependentProperties: list<IProperty> = []
  var _n = 0
  static var _count = 0

  def new(this.Fn)
    this._n = Effect._count
    Effect._count += 1
  enddef

  def Execute()
    var prevActive = gActiveEffect
    gActiveEffect = this
    this.ClearDependencies()
    Begin()
    try
      this.Fn()
    finally
      Commit()
      gActiveEffect = prevActive
    endtry
  enddef

  def ClearDependencies()
    for property in this.dependentProperties
      property.RemoveEffect(this)
    endfor
    this.dependentProperties = []
  enddef

  def String(): string
    return $'E{this._n}:' .. substitute(string(this.Fn), 'function(''\(.\+\)'')', '\1', '')
  enddef
endclass

class EffectsQueue
  var _q: list<Effect> = []
  var _start: number = 0

  static var max_size = get(g:, 'libreactive_queue_size', 10000)

  def Items(): list<Effect>
    return this._q[this._start : ]
  enddef

  def Empty(): bool
    return this._start == len(this._q)
  enddef

  def Push(effect: Effect)
    this._q->add(effect)

    if len(this._q) > EffectsQueue.max_size
      throw $'[Reactive] Potentially recursive effects detected (effects max size = {EffectsQueue.max_size}).'
    endif
  enddef

  def Pop(): Effect
    ++this._start
    return this._q[this._start - 1]
  enddef

  def Reset()
    this._q = []
    this._start = 0
  enddef
endclass
# }}}

# Global state {{{
export const DEFAULT_POOL = '__DEFAULT__'

var gActiveEffect: Effect = null_object
var gTransaction = 0 # 0 = not in a transaction, >=1 = inside transaction, >1 = in nested transaction
var gQueue = EffectsQueue.new()
var gPropertyRegistry: dict<list<IProperty>> = {}
# }}}

# Transactions {{{
export def Begin()
  gTransaction += 1
enddef

export def Commit()
  if gTransaction > 1
    --gTransaction
    return
  endif

  try
    while !gQueue.Empty()
      gQueue.Pop().Execute()
    endwhile
  finally
    gTransaction = 0
    gQueue.Reset()
  endtry
enddef

export def Transaction(Body: func())
  Begin()
  Body()
  Commit()
enddef
# }}}

# Properties {{{
export class Property implements IProperty
  var value: any = null
  var _effects: list<Effect> = []

  def new(this.value = v:none, pool = DEFAULT_POOL)
    this.Register(pool)
  enddef

  def Register(pool: string)
    if !gPropertyRegistry->has_key(pool)
      gPropertyRegistry[pool] = []
    endif
    gPropertyRegistry[pool]->add(this)
  enddef

  def Get(): any
    if gActiveEffect != null && gActiveEffect->NotIn(this._effects)
      this._effects->add(gActiveEffect)
      gActiveEffect.dependentProperties->add(this)
    endif

    return this.value
  enddef

  def Set(value: any, force = false)
    if !force && (value == this.value)
      return
    endif

    this.value = value

    Begin()
    for effect in this._effects
      if effect->NotIn(gQueue.Items())
        gQueue.Push(effect)
      endif
    endfor
    Commit()
  enddef

  def RemoveEffect(effect: Effect)
    effect->RemoveFrom(this._effects)
  enddef

  def Clear()
    this._effects = []
  enddef

  def Effects(): list<string>
    return mapnew(this._effects, (_, eff: Effect): string => eff.String())
  enddef

  def String(): string
    return printf('%s', this.value) .. ' [' .. printf('%s', join(this.Effects(), ', ')) .. ']'
  enddef
endclass
# }}}

# Functions {{{
export def CreateEffect(Fn: func())
  if gActiveEffect != null
    throw 'Nested effects detected: creating an effect within another effect is not allowed.'
  endif

  var runningEffect = Effect.new(Fn)

  runningEffect.Execute() # Necessary to bind to dependent signals
enddef

export def Memo(pool = DEFAULT_POOL): Property
  return Property.new(v:none, pool)
enddef

export def CreateMemo(p: Property, Fn: func(): any): func(): any
  CreateEffect(() => p.Set(Fn()))
  return p.Get
enddef

export def Clear(poolName: string, hard = false)
  const pools = empty(poolName) ? keys(gPropertyRegistry) : [poolName]

  for pool in pools
    if gPropertyRegistry->has_key(pool)
      for property in gPropertyRegistry[pool]
        property.Clear()
      endfor

      if hard
        gPropertyRegistry[pool] = []
        gPropertyRegistry->remove(pool)
      endif
    endif
  endfor
enddef

export def PoolStats(poolName = null_string): list<dict<any>>
  var stats: list<dict<any>> = []
  var pools = (poolName == null ? keys(gPropertyRegistry) : [poolName])

  for pool in pools
    var n = len(gPropertyRegistry[pool])

    stats->add({
      pool: pool,
      n_properties: n,
      values: mapnew(gPropertyRegistry[pool], (_, p: Property) => p.String()),
    })
  endfor

  return stats
enddef
# }}}
