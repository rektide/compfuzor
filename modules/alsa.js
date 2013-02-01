#!/usr/bin/env node

var Q= require("q"),
  fs= require("fs"),
  path= require("path")

var readDir= Q.nfbind(fs.readDir),
  readFile= Q.nfbind(fs.readFile)

var AUTORUN= 3

function __matrixize(components){
	var agg= [],
	  k= []
	for(var i= 0; i< arguments.length; ++i){
		k= k.concat(arguments[i])
		agg.push(k)
		k= k.concat(null)
		agg.push(k)
	}
	return agg
}

var addrMatrix= __matrixize("/proc/asound/card","/pcm","","/sub")
addrMatrix.phrase= __phrase
function __phrase(c,p,isPlaybackNotCapture,s){
	var val,
	  hasS= s!==undefined,
	  hasP= p!==undefined
	if(hasS){
		val= this[7]
		val[7]= s
	}
	if(hasS || hasP){
		if(!hasS)
			val= this[5]
		val[4]= isPlaybackNotCapture? "p": "c"
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
	  val= {addr:addr},
	  all= __buildExtract(addr,["id"],val),
	  playbacks= __resolveMore([],pMaker).then(__assignTo.bind(val,"playbacks")),
	  captures= __resolveMore([],cMaker).then(__assignTo.bind(val,"captures"))
	all.push(playbacks,captures)
	Q.allResolved(all).then(function(v){
		console.log("RESOLVED",v,v[0].valueOf())
	})
	return Q.allResolved(all).then(__checkException.bind(val))
	//return Q.allResolved(all).then(__empty)
}.bind(addrMatrix)

var cop= function(c,p,isPlayback){
	var maker= function(i){
		return sub(c,p,isPlayback,i)
	}
	var addr= this.phrase(c,p,isPlayback),
	  val= {addr:addr},
	  all= __buildExtract(addr,["info"],val),
	  subs= __resolveMore([],maker).then(__assignTo.bind(val,"subs"))
console.log("cop",addr)
	all.push(subs)
	return Q.allResolved(all).then(__checkException.bind(val))
}.bind(addrMatrix)


function __printPromisary(s,c){
	c= c||[]
	if(!s){
		console.log("nop")
		return
	}
	if(s.valueOf){
		s=s.valueOf()
	}
	if(s.exception){
		console.log("ex",s.exception)
		return
	}
	if(s instanceof Array){
		console.log("child",c)
		for(var i in s){
			var v= s[i]
			c.push(i)
			__printPromisary(v,c)
		}
		return
	}
	console.log("ey",s,c.join(":"))
}

function __more(fn,arr){
	arr.push(fn(arr.length))
}

function __lotsMore(fn,arr){
	for(var i= 0; i< AUTORUN; ++i){
		arr.push(fn(arr.length))
	}
}

function __resolveMore(s,make){
	function tryAgain(fn,s){
		if(this instanceof Function){
			s= fn
			fn= this
		}
		while(s.length){
			var last= s[s.length].valueOf()
			if(last.exception){
				console.log("x",last.exception)
			}else{
				__lotsMore(fn,s)
				return Q.all(s).then(arguments.callee)
			}
			s.pop()
		}
		throw "resolved nothing"
	}
	__lotsMore(make,s)
	return Q.all(s).then(tryAgain.bind(make))
}

var sub= function(c,p,isPlayback,s){
	var addr= this.phrase(c,p,isPlayback,s),
	  val= runAll(addr,["hw_params","info","prealloc","prealloc_max","status","sw_params"])
	return val
}.bind(addrMatrix)

function runAll(addr,files,val){
	val= val||{addr:addr}
	return Q.allResolved(__buildExtract(addr,files,val)).then(__empty)
}

function __buildExtract(addr,files,val){ // perhaps an alternate pattern might be trying the first entry first, then follow up
	val= val||{addr:addr}
	var all= files.map(function(addr,name,i,arr){
console.log("file",addr+path.sep+name,this)
		return readFile(addr+path.sep+name,"utf8").then(__assignTo.bind(this,name))
	}.bind(val,addr))
	return all
}

function __this(){return this}



function __assignTo(name,data){
	console.log("ASSIGNED",this,name,data)
	this[name]= data
	return data
//	return Q.when(data,function(name,d){
//console.log("assigning",name,d)
//		this[name]= d;
//		return d
//	}.bind(this,name),function(){console.log("failed",this.val)}.bind({val:name}))
}

function __empty(d){
	try{
		return __checkException.call(d)
	}catch(e){
		if(d.addr)
			console.log("aborted",d.addr)
	}
}

function __checkException(){
	var keys= Object.keys(this)
console.log("check keys",keys)
	for(var i in keys){
		var key= keys[i],
		  val= this[key],
		  res= val && val.valueOf && val.valueOf()
__printPromisary(this[key])
		if(!this.hasOwnProperty(key))
			continue
		if(key=="addr")
			continue
		if(!isNaN(key) && res.exception){ // exceptions do not count
console.log("exception",res.exception)
			continue
		}
console.log("check ok, had",key)
		return this
	}
	if(this.exception)
		console.log("exception",this.exception)
	if(this.addr)
		throw "No context accrued on "+this.addr
	else
		throw "No context accrued"
}

var card0= card(0)
card0.then(function(d){
	console.log("GOT",d)
	return d
}).done()
