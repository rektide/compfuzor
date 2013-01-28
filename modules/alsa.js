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
		k= k.concat(null,"/")
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
	var maker= function(i){
		return sub(c,p,+i,false)
	}

	var addr= this.phrase(c,p,true),
	  val= {},
	  all= __buildExtract(addr,["info"],val),
	  s= __resolveMore([],maker),
	  subs= s.then(__assignTo.bind(val,"subs"))
	all.push(subs)
	return Q.allResolved(all).then(__this.bind(val))
}

function __resolveMore(s,make){
	var resolve= function(s){
		s= s||[]
		for(var i= 0; i< AUTORUN; ++i){
			this.push(this(s.length))
		}
		return s
	}.bind(make)
	var try= function(s){
		s= s||[]
		return Q.allResolve(this(s)).then(function(s){
			var last= s[s.length-1]
			if(last && !last.valueOf().exception)
				return try(s)
			else
				return s
		})
	}.bind(resolve)
	return try()
}

function sub(c,p,isPlayback,s){
	var addr= this.phrase(c,p,isPlayback,s),
	  val= runAll(addr,["hw_params","info","prealloc","prealloc_max","status","sw_params"])
	return val
}

function runAll(addr,files,val){
	val= val||{}
	return Q.allResolved(__buildExtract(addr,files,val)).then(__this.bind(val))
}

function __buildExtract(addr,files,val){ // perhaps an alternate pattern might be trying the first entry first, then follow up
	val= val||{}
	var all= files.map(function(name,i,arr){
		return readFile(addr+name,"utf8").then(_assignTo(name,val))
	})
	return all
}

function __this(){return this}

function __assignTo(name,data){
	this[name]= data
}
