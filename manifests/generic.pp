class mongodb-tayra-backup::generic()
{

	$backup_skel_dir = ['/data/', '/data/backup', '/data/backup/archive', '/data/backup/dump', '/data/backup/incremental_backup', '/data/backup/tayra']

  	file { "$backup_skel_dir":
    	ensure => 'directory',
    	owner  => 'root',
    	group  => 'root',
    	mode   => '0750'
  	}

  	package { "unzip":
        ensure => installed,
    }
	
	# unzip and place tayra files under /data/backup/tayra
	file { "/data/backup/tayra/Tayra-0.8.1.Beta3.zip":
	    owner   => root,
        group   => root,
        mode    => 644,
        ensure  => present,
		source => 'puppet:///modules/mongodb-tayra-backup/Tayra-0.8.1.Beta3.zip'
		notify => Exec['unzip'],
	}

	exec { "unzip":
  		command     => 'unzip /data/backup/tayra/Tayra-0.8.1.Beta3.zip -d /data/backup/tayra',
  		user        => 'root',
  		require     => File["/data/backup/tayra"],
  		unless 		=> "/usr/bin/test -f /data/backup/tayra/backup.sh",
  		refreshonly => true,
	}

	
	file { "/usr/local/bin/mongo-tayra-backup.sh":
	    owner   => root,
        group   => root,
        mode    => 755,
        ensure  => present,
		source  => 'puppet:///modules/mongodb-tayra-backup/mongo-tayra-backup.sh',
	}

	file { "/data/backup/tayra/backup.sh":
		ensure  => present,
		mode => 755,
	}

	file { "/data/backup/tayra/restore.sh":
  		ensure  => present,
  		mode => 755,
	}
	
	file_line { 'crontab-mongo-tayra-backup':
        path  => '/etc/crontab',
        line  => '0 6 * * * root /usr/local/bin/mongo-tayra-backup.sh',
	}

}
