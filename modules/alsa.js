#!/usr/bin/env node

var Q= require("q"),
  fs= require("fs")

var readDir= Q.nfbind(FS.readDir)

var matches= []


function playback(card,n){

}

function capture(card,n){
}

function sub(c,p,s,isPlayback){
        var base= ["/proc/asound/card",c,"/pcm"+p+isPlayback?"p/sub":"c/sub",s,null]
	function _la(arr,v){
		arr[arr.length-1]= v
		return arr.join("")
	}

	var val= {}
	var f= function(name){
		var p= this[name]= readFile(_la(base,name)).then(function(){
			if(--this.ref==0){
				this.ready.resolve(this)
			}
			return this
		}.bind(this))
		l.push(p)
		return p
	}.bind(val)
	var all= ["hw_params","info","prealloc","prealloc_max","status","sw_params"].map(function(v,i,arr){
		f(v)
	})
	return Q.all(all)
}

function slurpCard(n){
	var id= readFile("/proc/asound/card"+n+"/id"),
}

function slurpCard(n,start){
	n= n||0
	start= start||[]
	readDir("/proc/asound/card"+n).then(function(n,entries){
		for(var e in entries){
			var c= /pcm(\d+)c/.exec(data),
			 p= /pcm(\d+)c/.exec(data),
		}
		slurpCard(this+1)
	}.bind(start,n)).fail
}


