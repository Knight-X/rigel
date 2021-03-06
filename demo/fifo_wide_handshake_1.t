local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

W = 128
H = 64
T = 8

inp = S.parameter("inp",types.uint(8))
plus100 = RM.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )

------------
local p100 = RM.makeHandshake( RM.map( plus100, T) )
------------
ITYPE = types.array2d( types.uint(8), T )
local inp = R.input( R.Handshake(ITYPE) )
local regs = { R.instantiateRegistered("f1", RM.fifo(ITYPE,128,nil,W,H,T) ) }

------
local pinp = R.applyMethod("l1",regs[1],"load")
local out = R.apply( "plus100", p100, pinp )
------
hsfn = RM.lambda( "fifo_wide", inp, R.statements{out, R.applyMethod("s1",regs[1],"store",inp)}, regs )
------------

harness.axi( "fifo_wide_handshake_1", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)