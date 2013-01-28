#!/usr/bin/env node

var Q= require("q"),
  fs= require("fs")

var readDir= Q.nfbind(FS.readDir)

var AUTORUN= 3

function matrixize(components){
	var agg= [],
	  k= []
	for(var i= 0; i< arguments.legnth; ++i){
		k= k.concat(arguments[i]
		agg.push(k)
		k= k.concat(null)
		agg.push(k)
	}
	return agg
}

var addrMatrix= matrixize("/proc/asound/card","/pcm","","/sub")
addrMatrix.phrase= _phrase
function phrase(c,p,isPlaybackNotCapture,s){
	var val
	if(s){
		val= this[5]
		val[7]= s
	}else if(p){
		val= this[3]
	}

	if(s||p){
		val[5]= isPlaybackNotCapture? "p": "c"
		val[3]= p
	}else{
		val= this[1]
	}
	val[1]= c
	return val.join("")
}

var card= function(c){
	
}.bind(addrMatrix)

var playback= function(c,p){
	sub(c,p,0,true)
	sub(c,p,1,true)
	sub(c,p,2,true)
}

function capture(c,p){
	sub(c,p,0,false)
	sub(c,p,1,false)
	sub(c,p,2,false)
}

function __ready(val){
	if(--this.ref==0){
		this.ready.resolve(this)
	}
	return val
}

function __readContext(name,addr){
	return this[name]= readFile(addr).then(__ready.bind(this))
}

function sub(c,p,isPlayback,s){
	var addr= this.phrase(c,p,isPlayback,s),
	  val= {}
	var all= ["hw_params","info","prealloc","prealloc_max","status","sw_params"].map(function(name,i,arr){
		return __readyContext.call(val,name,addr)
	})
	return Q.all(all)
}

