#!/usr/bin/env node

var Q= require("q"),
  fs= require("fs")

var readDir= Q.nfbind(fs.readDir),
  readFile= Q.nfbind(fs.readFile)

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
	var pMaker= function(i){
		return cop(c,i,true)
	}
	var cMaker= function(i){
		return cop(c,i,false)
	}

	var addr= this.phrase(c),
	  val= {},
	  all= __buildExtract(addr,["id"],val),
	  playbacks= __resolveMore([],pMaker).then(__assignTo.bind(val,"playbacks")),
	  captures= __resolveMore([],cMaker).then(__assignTo.bind(val,"captures"))
	all.push(playbacks,captures)
	return Q.allResolved(all).then(__checkException(val))
}

var cop= function(c,p,isPlayback){
	var maker= function(i){
		return sub(c,p,isPlayback,i)
	}

	var addr= this.phrase(c,p,isPlayback),
	  val= {},
	  all= __buildExtract(addr,["info"],val),
	  subs= __resolveMore([],maker).then(__assignTo.bind(val,"subs"))
	all.push(subs)
	return Q.allResolved(all).then(__checkException(val))
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
			while(!last || last.valueOf().exception){
				s.pop()
				last= s[s.length-1]
			}
			return s
		})
	}.bind(resolve)
	return try([])
}

function sub(c,p,isPlayback,s){
	var addr= this.phrase(c,p,isPlayback,s),
	  val= runAll(addr,["hw_params","info","prealloc","prealloc_max","status","sw_params"])
	return val
}

function runAll(addr,files,val){
	val= val||{}
	return Q.allResolved(__buildExtract(addr,files,val)).then(__checkException.bind(val))
}

function __buildExtract(addr,files,val){ // perhaps an alternate pattern might be trying the first entry first, then follow up
	val= val||{}
	var all= files.map(function(name,i,arr){
		return readFile(addr+name,"utf8").then(__assignTo.bind(val,name))
	})
	return all
}

function __this(){return this}

function __assignTo(name,data){
	return Q.when(data,function(d){
		this[name= d;
		return d
	}.bind(this.name))
}

function __checkException(val){
	var keys= Object.keys(val)
	for(var i in keys){
		if(!val.hasOwnProperty(i))
			continue
		return val
	}
	throw "No context accured"
}

