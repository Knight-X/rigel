require("common")
local IR = require("ir")

local types = {}

TypeFunctions = {}
TypeMT = {__index=TypeFunctions, __tostring=function(ty)
            local const = sel(ty.constant,"_const","")
  if ty.kind=="bool" then
    return "bool"..const
  elseif ty.kind=="null" then
    return "null"
  elseif ty.kind=="int" then
    return "int"..ty.precision..const
  elseif ty.kind=="uint" then
    return "uint"..ty.precision..const
  elseif ty.kind=="bits" then
    return "bits"..ty.precision..const
  elseif ty.kind=="float" then
    return "float"..ty.precision..const
  elseif ty.kind=="array" then
    return tostring(ty.over).."["..table.concat(ty.size,",").."]"
  elseif ty.kind=="tuple" then
    return "{"..table.concat(map(ty.list, function(n) return tostring(n) end), ",").."}"
  elseif ty.kind=="opaque" then
    return "opaque_"..ty.str
  end

  print("Error, typeToString input doesn't appear to be a type, ",ty.kind)
  assert(false)
end}

types._bool=setmetatable({kind="bool",constant=false}, TypeMT)
types._boolconst=setmetatable({kind="bool",constant=true}, TypeMT)
function types.bool(const) if const==true then return types._boolconst else return types._bool end end

types._null=setmetatable({kind="null"}, TypeMT)
function types.null() return types._null end

types._opaque={}
function types.opaque( str, X )
  assert(X==nil)
  types._opaque[str] = types._opaque[str] or setmetatable({kind="opaque",str=str},TypeMT)
  return types._opaque[str]
end

types._bits={[true]={},[false]={}}
function types.bits( prec, const )
  assert(prec==math.floor(prec))
  local c = (const==true)
  types._bits[c][prec] = types._bits[c][prec] or setmetatable({kind="bits",precision=prec,constant=c},TypeMT)
  return types._bits[c][prec]
end

types._uint={[true]={},[false]={}}
function types.uint(prec,const)
  err(prec==math.floor(prec), "uint precision should be integer, but is "..tostring(prec) )
  local c = (const==true)
  types._uint[c][prec] = types._uint[c][prec] or setmetatable({kind="uint",precision=prec,constant=c},TypeMT)
  return types._uint[c][prec]
end

types._int={[true]={},[false]={}}
function types.int(prec,const)
  assert(prec==math.floor(prec))
  local c = (const==true)
  types._int[c][prec] = types._int[c][prec] or setmetatable({kind="int",precision=prec,constant=c},TypeMT)
  return types._int[c][prec]
end

types._float={[true]={},[false]={}}
function types.float(prec,const)
  assert(prec==math.floor(prec))
  local c = (const==true)
  types._float[c][prec] = types._float[c][prec] or setmetatable({kind="float",precision=prec,constant=c},TypeMT)
  return types._float[c][prec]
end

types._array={}

function types.array2d( _type, w, h )
  err( types.isType(_type), "first index to array2d must be type" )
  assert( type(w)=="number" )
  err( type(h)=="number" or h==nil, "array2d h must be nil or number, but is:"..type(h))
  if h==nil then h=1 end -- by convention, 1d arrays are 2d arrays with height=1
  err(w==math.floor(w), "non integer array width "..tostring(w))
  assert(h==math.floor(h))

  -- dedup the arrays
  local ty = setmetatable( {kind="array", over=_type, size={w,h}}, TypeMT )
  return deepsetweak(types._array, {_type,w,h}, ty)
end

types._tuples = {}

function types.tuple( list )
  assert(type(list)=="table")
  assert(keycount(list)==#list)
  err(#list>0, "no empty tuple types!")

  -- we want to allow a tuple with one item to be a real type, for the same reason we want there to be an array of size 1.
  -- This means we can parameterize a design from tuples with 1->N items and it will work the same way.
  --if #list==1 and types.isType(list[1]) then return list[1] end

  --map( list, function(n) print("types.tuple",n);assert( types.isType(n) ) end )
  types._tuples[#list] = types._tuples[#list] or {}
  local tup = setmetatable( {kind="tuple", list = list }, TypeMT )
  assert(types.isType(tup))
  local res = deepsetweak( types._tuples[#list], list, tup )
  assert(types.isType(res))
  assert(#res.list==#list)
  return res
end

local boolops = {["or"]=1,["and"]=1,["=="]=1,["xor"]=1} -- bool -> bool -> bool
local cmpops = {["=="]=1,["~="]=1,["<"]=1,[">"]=1,["<="]=1,[">="]=1} -- number -> number -> bool
local binops = {["|"]=1,["^"]=1,["&"]=1,["<<"]=1,[">>"]=1,["+"]=1,["-"]=1,["%"]=1,["*"]=1,["/"]=1}
-- these binops only work on ints
local intbinops = {["<<"]=1,[">>"]=1,["and"]=1,["or"]=1,["^"]=1}
-- ! does a logical not in C, use 'not' instead
-- ~ does a bitwise not in C
local unops = {["not"]=1,["-"]=1}
appendSet(binops,boolops)
appendSet(binops,cmpops)

-- returns resultType, lhsType, rhsType
-- ast is used for error reporting
function types.meet( a, b, op, loc)
  assert(types.isType(a))
  assert(types.isType(b))
  assert(type(op)=="string")
  assert(type(loc)=="string") -- code location of op, in case there is an error
  
  assert(getmetatable(a)==TypeMT)
  assert(getmetatable(b)==TypeMT)

  local treatedAsBinops = {["select"]=1, ["vectorSelect"]=1,["array"]=1, ["mapreducevar"]=1, ["dot"]=1, ["min"]=1, ["max"]=1}

  if a:isTuple() and b:isTuple() then
    assert(a==b)
    return a,a,a
  elseif a:isArray() and b:isArray() then
    if a:arrayLength() ~= b:arrayLength() then
      print("Type error, array length mismatch")
      return nil
    end
    
    if op=="dot" then
      local rettype,at,bt = types.meet(a.over,b.over,op,loc)
      local convtypea = types.array( at, a:arrayLength() )
      local convtypeb = types.array( bt, a:arrayLength() )
      return rettype, convtypea, convtypeb
    elseif cmpops[op] then
      -- cmp ops are elementwise
      local rettype,at,bt = types.meet(a.over,b.over,op,loc)
      local convtypea = types.array( at, a:arrayLength() )
      local convtypeb = types.array( bt, a:arrayLength() )
      
      local thistype = types.array( types.bool(), a:arrayLength() )
      return thistype, convtypea, convtypeb
    elseif binops[op] or treatedAsBinops[op] then
      -- do it pointwise
      local thistype = types.array2d( types.meet( a.over, b.over, op, loc ), (a:arrayLength())[1], (a:arrayLength())[2] )
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.array(types.float(32), a:arrayLength() )
      return thistype, thistype, thistype
    else
      print("OP",op)
      assert(false)
    end
      
  elseif a.kind=="int" and b.kind=="int" then
    local prec = math.max(a.precision,b.precision)
    local thistype = types.int(prec)
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP",op)
      assert(false)
    end
  elseif a.kind=="uint" and b.kind=="uint" then
    local prec = math.max(a.precision,b.precision)
    local thistype = types.uint(prec)
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP2",op)
      assert(false)
    end
  elseif (a.kind=="uint" and b.kind=="int") or (a.kind=="int" and b.kind=="uint") then
    
    local ut = a
    local t = b
    if a.kind=="int" then ut,t = t,ut end
    
    local prec
    if ut.precision==t.precision and t.precision < 64 then
      prec = t.precision * 2
    elseif ut.precision<t.precision then
      prec = math.max(a.precision,b.precision)
    else
      error("Can't meet a "..tostring(ut).." and a "..tostring(t))
    end
    
    local thistype = types.int(prec)
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      return thistype, thistype, thistype
    else
      print( "operation " .. op .. " is not implemented for aType:" .. a.kind .. " bType:" .. b.kind .. " " )
      assert(false)
    end
    
  elseif (a.kind=="float" and (b.kind=="uint" or b.kind=="int")) or 
    ((a.kind=="uint" or a.kind=="int") and b.kind=="float") then
    
    local thistype
    local ftype = a
    local itype = b
    if b.kind=="float" then ftype,itype=itype,ftype end
    
    if ftype.precision==32 and itype.precision<32 then
      thistype = types.float(32)
    elseif ftype.precision==32 and itype.precision==32 then
      thistype = types.float(32)
    elseif ftype.precision==64 and itype.precision<64 then
      thistype = types.float(64)
    else
      assert(false) -- NYI
    end
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif intbinops[op] then
      error("Passing a float to an integer binary op "..op)
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP4",op)
      assert(false)
    end
    
  elseif a.kind=="float" and b.kind=="float" then
    
    local prec = math.max(a.precision,b.precision)
    local thistype = types.float(prec)
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif intbinops[op] then
      error("Passing a float to an integer binary op "..op)
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP3",op)
      assert(false)
    end
    
  elseif a.kind=="bool" and b.kind=="bool" then
    -- you can combine two bools into an array of bools
    if boolops[op]==nil and op~="array" then
      error("Internal error, attempting to meet two booleans on a non-boolean op: "..op)
      return nil
    end
    
    local thistype = types.bool()
    return thistype, thistype, thistype
  elseif a:isArray() and b:isArray()==false then
    -- we take scalar constants and duplicate them out to meet the other arguments array length
    local thistype, lhstype, rhstype = types.meet( a, types.array( b,a :arrayLength() ), op, loc )
    return thistype, lhstype, rhstype
  elseif a:isArray()==false and b:isArray() then
    local thistype, lhstype, rhstype = types.meet( types.array(a, b:arrayLength() ), b, op, loc )
    return thistype, lhstype, rhstype
  else
    error("Type error, meet not implemented for "..tostring(a).." and "..tostring(b)..", op "..op..", "..loc)
  end
  
  assert(false)
  return nil
end

-- check if type 'from' can be converted to 'to' (explicitly)
function types.checkExplicitCast(from, to, ast)
  assert(from~=nil)
  assert(to~=nil)

  if from==to then
    -- obvously can return true...
    return true
  elseif from:constSubtypeOf(to) then
    return true
  elseif to.kind=="bits" and from.kind=="bits" and to:verilogBits()>from:verilogBits() then
    return true -- allow padding
  elseif to.kind=="bits" or from.kind=="bits" then
    -- we can basically cast anything to/from raw bits. Type Safety?!?!?!
    err( from:verilogBits()==to:verilogBits(), "Error, casting "..tostring(from).." to "..tostring(to)..", types must have same number of bits")
    return true
  elseif from:isArray() and to:isArray() and from:arrayOver()==to:arrayOver() then
    -- we do allow you to explicitly cast arrays of different shapes but the same total size
    if from:channels()~=to:channels() then
      error("Can't change array length when casting "..tostring(from).." to "..tostring(to) )
    end

    return types.checkExplicitCast(from.over, to.over,ast)
  elseif from:isTuple() then
    local allbits = foldt( map(from.list, function(n) return n:isBits() end), andop, 'X')

    if allbits then
      -- we let you cast a tuple of bits {bits(a),bits(b),...} to whatever
      err(from:verilogBits() == to:verilogBits(), "tuple of bits size fail from:"..tostring(from).." to "..tostring(to))
      return true
    elseif #from.list==1 and from.list[1]==to then
      -- casting {A} to A
      return true
    elseif to:isArray() then
      local allTheSame = true
      for k,v in pairs(from.list) do if v:constSubtypeOf(from.list[1])==false then allTheSame=false end end

      if allTheSame and #from.list == to:channels() then
        -- casting {A,A,A,A} to A[4]
        return true
      elseif from.list[1]:isArray() then
        -- we can cast {A[a],A[b],A[c]..} to A[a+b+c]
        local ty, channels = from.list[1]:arrayOver(), 0
        map(from.list, function(t) assert(t:arrayOver()==ty); channels = channels + t:channels() end )
        err( channels==to:channels(), "channels don't match") 
        return true
      end
    end

    error("unknown tuple cast? "..tostring(from).." to "..tostring(to))

  elseif (from:isTuple()==false and from:isArray()==false) and to:isArray() then
    -- broadcast
    return types.checkExplicitCast(from, to.over, ast )
  elseif from:isArray() then
    if from:arrayOver():isBool() and from:channels()==to:sizeof()*8 then
      -- casting an array of bools to a type with the same number of bits is OK
      return true
    elseif from:channels()==1 and types.checkExplicitCast(from:arrayOver(),to,ast) then
      -- can explicitly cast an array of size 1 to a compatible type
      return true
    end

    error("Can't cast an array type to a non-array type. "..tostring(from).." to "..tostring(to)..ast.loc)
    return false
  elseif from.kind=="uint" and to.kind=="uint" then
    return true
  elseif from.kind=="int" and to.kind=="int" then
    return true
  elseif from.kind=="uint" and to.kind=="int" then
    return true
  elseif from.kind=="float" and to.kind=="uint" then
    return true
  elseif from.kind=="uint" and to.kind=="float" then
    return true
  elseif from.kind=="int" and to.kind=="float" then
    return true
  elseif from.kind=="int" and to.kind=="uint" then
    return true
  elseif from.kind=="int" and to.kind=="bool" then
    darkroom.error("converting an int to a bool will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.kind=="bool" and (to.kind=="int" or to.kind=="uint") then
    darkroom.error("converting a bool to an int will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.kind=="float" and to.kind=="int" then
    return true
  elseif from.kind=="float" and to.kind=="float" then
    return true
  else
    print("from",from,"to",to)
    assert(false) -- NYI
  end

  return false
end

---------------------------------------------------------------------
-- 'externally exposed' functions

function types.isType(ty)
  return getmetatable(ty)==TypeMT
end

-- is the type const?
function TypeFunctions:const()
  if self:isUint() or self:isInt() or self:isFloat() or self:isBool() or self:isBits() then
    return self.constant
  elseif self:isOpaque() then
    return true -- why not?
  elseif self:isArray() then
    return self:arrayOver():const()
  elseif self:isTuple() then
    return foldl(andop,true, map(self.list, function(v) return v:const() end ) )
  elseif self:isNull() then
    return true
  else
    print(":const",self)
    assert(false)
  end
end

-- if self is a subtype of A, this means self can be used in place of A
-- eg 'bool_const' is a subtype of 'bool'
function TypeFunctions:constSubtypeOf(A)
  if A==self then
    return true
  elseif A.kind~=self.kind then
    return false
  elseif self:isUint() or self:isInt() or self:isFloat() or self:isBool() or self:isBits() then
    if self:const() and A:makeConst()==self then
      return true
    else
      return false
    end
  elseif self:isTuple() then
    if #A.list~=#self.list then return false end
    return foldl( andop, true, map(self.list, function(t,k) return t:constSubtypeOf(A.list[k]) end) )
  elseif self:isArray() then
    local lenmatch = (self:arrayLength())[1]==(A:arrayLength())[1] and (self:arrayLength())[2]==(A:arrayLength())[2]
    return self:arrayOver():constSubtypeOf(A:arrayOver()) and lenmatch
  elseif self:isOpaque() then
    return self.str==A.str
  else
    print(":constSubtypeOf",self,A)
    assert(false)
  end
end

function TypeFunctions:makeConst()
  if self:const() then return self end

  if self:isUint() then
    return types.uint( self.precision, true )
  elseif self:isInt() then
    return types.int( self.precision, true )
  elseif self:isBits() then
    return types.bits( self.precision, true )
  elseif self:isFloat() then
    return types.float( self.precision, true )
  elseif self:isOpaque() then
    return self -- doesn't matter
  elseif self:isArray() then
    local L = self:arrayLength()
    return types.array2d( self:arrayOver():makeConst(),L[1],L[2])
  elseif self:isTuple() then
    return types.tuple(map(self.list,function(t) return t:makeConst() end ) )
  elseif self:isBool() then
    return types.bool(true)
  else
    print(":makeConst",self)
    assert(false)
  end
end

function TypeFunctions:stripConst()
  if self:isUint() then
    return types.uint( self.precision, false )
  elseif self:isInt() then
    return types.int( self.precision, false )
  elseif self:isFloat() then
    return types.float( self.precision, false )
  elseif self:isBits() then
    return types.bits( self.precision, false )
  elseif self:isOpaque() then
    return self -- doesn't matter
  elseif self:isArray() then
    local L = self:arrayLength()
    return types.array2d( self:arrayOver():stripConst(),L[1],L[2])
  elseif self:isTuple() then
    local typelist = map(self.list, function(t) return t:stripConst() end)
    return types.tuple(typelist)
  elseif self:isBool() then
    return types.bool(false)
  else
    print(":stripConst",self)
    assert(false)
  end
end


function TypeFunctions:isArray()  return self.kind=="array" end

function TypeFunctions:arrayOver()
  assert(self.kind=="array")
  return self.over
end

function TypeFunctions:baseType()
  if self.kind~="array" then return self end
  assert(type(self.over)~="array")
  return self.over
end


-- returns 0 if not an array
function TypeFunctions:arrayLength()
  if self.kind~="array" then return 0 end
  return self.size
end

function TypeFunctions:channels()
  if self.kind~="array" then return 1 end
  local chan = 1
  for k,v in ipairs(self.size) do chan = chan*v end
  return chan
end

function TypeFunctions:isTuple()  return self.kind=="tuple" end

function TypeFunctions:tupleList()
  if self.kind~="tuple" then return {self} end
  return self.list
end

-- if pointer is true, generate a pointer instead of a value
-- vectorN = width of the vector [optional]
function TypeFunctions:toTerraType(pointer, vectorN)
  local ttype

  if self:isFloat() and self.precision==32 then
    ttype = float
  elseif self:isFloat() and self.precision==64 then
    ttype = double
  elseif self:isUint() and self.precision<=8 then
    ttype = uint8
  elseif self:isInt() and self.precision<=8 then
    ttype = int8
  elseif self:isBool() then
    ttype = bool
  elseif self:isInt() and self.precision>16 and self.precision<=32 then
    ttype = int32
  elseif self:isInt() and self.precision>32 and self.precision<=64 then
    ttype = int64
  elseif self:isUint() and self.precision>32 and self.precision<=64 then
    ttype = uint64
  elseif self:isUint() and self.precision>16 and self.precision<=32 then
    ttype = uint32
  elseif self:isUint() and self.precision>8 and self.precision<=16 then
    ttype = uint16
  elseif self:isInt() and self.precision>8 and self.precision<=16 then
    ttype = int16
  elseif self:isArray() then
    assert(vectorN==nil)
    ttype = (self.over:toTerraType())[self:channels()]
  elseif self.kind=="tuple" then
    ttype = tuple( unpack(map(self.list, function(n) return n:toTerraType(pointer, vectorN) end)) )
  elseif self.kind=="opaque" then
    ttype = &opaque
  elseif self.kind=="null" then
    ttype = &opaque
  else
    print(":toTerraType",self)
    print(debug.traceback())
    assert(false)
  end

  if vectorN then
    if pointer then return &vector(ttype,vectorN) end
    return vector(ttype,vectorN)
  else
    if pointer then return &ttype end
    return ttype
  end

  print(types.typeToString(_type))
  assert(false)

  return nil
end

function TypeFunctions:valueToTerra(value)
  if self:isUint() or self:isFloat() or self:isInt() then
    assert(type(value)=="number")
    return `[self:toTerraType()](value)
  elseif self:isArray() then
    assert(type(value)=="table")
    assert(#value==self:channels())
    local tup = map( value, function(v) return self:arrayOver():valueToTerra(v) end )
    return `[self:toTerraType()](array(tup))
  elseif self:isTuple() then
    assert(type(value)=="table")
    assert(#value==#self.list)
    local tup = map( value, function(v,k) return self.list[k]:valueToTerra(v) end )
    return `[self:toTerraType()]({tup})
  else
    print("TypeFunctions:valueToTerra",self)
    assert(false)
  end
end

function TypeFunctions:sizeof()
  return terralib.sizeof(self:toTerraType())
end

function TypeFunctions:verilogBits()
  if self:isBool() then 
    return 1
  elseif self==types.null() then
    return 0
  elseif self:isTuple() then
    local sz = 0
    for _,v in pairs(self.list) do sz = sz + v:verilogBits() end
    return sz
  elseif self:isArray() then
    return self:arrayOver():verilogBits()*self.size[1]*self.size[2]
  elseif self:isInt() or self:isUint() then
    return self.precision
  elseif self:isBits() then
    return self.precision
  elseif self:isFloat() then
    return self.precision
  elseif self:isOpaque() then
    return 0
  else
    print(self)
    assert(false)
  end
end

function TypeFunctions:isFloat() return self.kind=="float" end
function TypeFunctions:isBool() return self.kind=="bool" end
function TypeFunctions:isInt() return self.kind=="int" end
function TypeFunctions:isUint() return self.kind=="uint" end
function TypeFunctions:isBits() return self.kind=="bits" end
function TypeFunctions:isNull() return self.kind=="null" end
function TypeFunctions:isOpaque() return self.kind=="opaque" end

function TypeFunctions:isNumber()
  return self.kind=="float" or self.kind=="uint" or self.kind=="int"
end

function TypeFunctions:fakeValue()
  if self:isInt() or self:isUint() or self:isFloat() then
    return 0
  elseif self:isArray() then
    local t = {}
    for i=1,self:channels() do table.insert(t,self:arrayOver():fakeValue()) end
    return t
  elseif self:isTuple() then
    local t = {}
    for k,v in ipairs(self.list) do
      table.insert(t,v:fakeValue())
    end
    return t
  else
    err(false, "could not create fake value for "..tostring(self))
  end
end

-- check that v is a lua value convertable to this type
function TypeFunctions:checkLuaValue(v)
  if self:isArray() then
    err( type(v)=="table", "if type is an array, v must be a table")
    err( #v==keycount(v), "lua table is not an array (unstructured keys)")
    err( #v==self:channels(), "incorrect number of channels, is "..(#v).." but should be "..self:channels() )
    for i=1,#v do
      self:arrayOver():checkLuaValue(v[i])
    end
  elseif self:isTuple() then
    err( type(v)=="table", "if type is a tuple, v must be a table")
    err( #v==#self.list, "incorrect number of channels, is "..(#v).." but should be "..#self.list )
    map( v, function(n,k) self.list[k]:checkLuaValue(n) end )
  elseif self:isFloat() then
    err( type(v)=="number", "float must be number")
  elseif self:isInt() then
    err( type(v)=="number", "int must be number")
    err( v==math.floor(v), "integer systolic constant must be integer")
  elseif self:isUint() or self:isBits() then
    err( type(v)=="number", "uint/bits must be number but is "..type(v))
    err( v>=0, "systolic uint/bits const must be positive")
    err( v<math.pow(2,self:verilogBits()), "Constant value "..tostring(v).." out of range for type "..tostring(self))
  elseif self:isBool() then
    err( type(v)=="boolean", "bool must be lua bool")
  elseif self:isOpaque() then
    err( v==0, "opaque must be 0 but is "..tostring(v))
  else
    print("NYI - ",self)
    assert(false)
  end

end

return types