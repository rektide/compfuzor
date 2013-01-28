define reprepro($origin= "archive.eldergods.com", $label= "ElderArchive", $codename= "main", $arch= "i386 amd64", $components= "main", $desc= "$label/$codename Debian repository", $keyid= "") {
	$fullmodule = "reprepro-$title"
	$dir = "/srv/$fullmodule"
	package { "reprepro":
		ensure => "latest",
	}
	puppetry::srv-er { "$fullmodule":
		gnupg => true,
	}
	puppetry::dir { "$dir/conf":
		module => "$fullmodule",
		require => Puppetry::Srv-er["$fullmodule"],
	}
	puppetry::dir { "$dir/www":
		module => "$fullmodule",
		mode => 0755,
		require => Puppetry::Srv-er["$fullmodule"],
	}
	puppetry::template { "$dir/conf/distributions":
		module => "$fullmodule",
		template => "reprepro/conf/distributions.erb",
		require => Puppetry::Dir["$dir/conf"],
	}
	puppetry::template { ["$dir/conf/options"]:
		module => "$fullmodule",
		template => "reprepro/conf/options.erb",
		require => Puppetry::Dir["$dir/conf"]
	}
	puppetry::template { "$dir/conf/override.$codename":
		module => "$fullmodule",
		template => "reprepro/conf/override.erb",
		require => Puppetry::Dir["$dir/conf"]
	}
	puppetry::link { "$dir/www/pool":
		module => "$fullmodule",
		target => "$dir/pool",
		require => Puppetry::Dir["$dir/www"]
	}
	puppetry::link { "$dir/www/dists":
		module => "$fullmodule",
		target => "$dir/dists",
		require => Puppetry::Dir["$dir/www"]
	}
}
