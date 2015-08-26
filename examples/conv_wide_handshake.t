local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require("harness")
local C = require "examplescommon"

T = 8 -- throughput
--ConvRadius = 1
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)

inputW = 128
inputH = 64

-- expand to include crop region
--W = upToNearest(T,128+ConvWidth-1)
--H = 64+ConvWidth-1

W = inputW
H = inputH

local convolve = C.convolveConstant( types.uint(8), ConvWidth, range(ConvArea), 8 )
-------------
BASE_TYPE = types.array2d( types.uint(8), T )
ITYPE = d.Stateful(BASE_TYPE)
inp = d.input( ITYPE )

--I = d.apply("crop", d.cropSeq(types.uint(8),W,H,T,ConvWidth,0,ConvWidth,0,0), inp)
convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ) ), convLB )
convpipe = d.apply( "conv", d.makeStateful( d.map( convolve, T ) ), convstencils )
convpipe = d.apply( "border", darkroom.borderSeq( types.uint(8), inputW, inputH, T, ConvWidth-1, 0, ConvWidth-1, 0, 0 ), convpipe ) -- cut off junk

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------
hsfn = d.makeHandshake(convpipe)

harness.axi( "conv_wide_handshake", hsfn, BASE_TYPE, nil, nil, inputW, inputH, BASE_TYPE, inputW, inputH )