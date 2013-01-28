import "reprepro"

class srv-reprepro-testing {
	reprepro { "testing": 
		arch => "armel i386 amd64",
		keyid => "5ACF4AC4"
	}
	puppetry::link { "/etc/lighttpd2/links.d/com.eldergods.archive":
		module => "reprepro-testing",
		target => "/srv/reprepro-testing/www"
	}
}
