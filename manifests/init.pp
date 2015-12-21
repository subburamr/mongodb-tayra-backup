class mongodb-tayra-backup()
{

	file { [ '/data',
         	'/data/backup',
         	'/data/backup/archive',
         	'/data/backup/dump',
		'/data/backup/incremental_backup',
		'/data/backup/tayra', ]:
           	ensure => directory,
                owner  => 'root',
                group  => 'root',
                mode   => '0644'
	}

  	package { "unzip":
        	ensure => installed,
    	}

        package { "bc":
                ensure => installed,
        }

        package { "expect":
                ensure => installed,
        }
	
	# unzip and place tayra files under /data/backup/tayra
	file { "/data/backup/tayra/Tayra-0.8.1.Beta3.zip":
		owner   => root,
        	group   => root,
        	mode    => 644,
        	ensure  => present,
		source  => 'puppet:///modules/mongodb-tayra-backup/Tayra-0.8.1.Beta3.zip',
		notify  => Exec['unzip'],
	}

	exec { "unzip":
  		command     => '/usr/bin/unzip /data/backup/tayra/Tayra-0.8.1.Beta3.zip -d /data/backup/tayra',
  		user        => 'root',
  		unless	    => "/usr/bin/test -f /data/backup/tayra/backup.sh",
  		refreshonly => true,
	}

	
	file { "/usr/local/bin/mongo-tayra-backup.sh":
		owner   => root,
        	group   => root,
        	mode    => 755,
        	ensure  => present,
		source  => 'puppet:///modules/mongodb-tayra-backup/mongo-tayra-backup.sh',
	}

	file { [ '/data/backup/tayra/backup.sh',
		'/data/backup/tayra/restore.sh', ]:
		ensure  => present,
		mode => 755,
	}

        file { "/data/backup/tayra/backup_expect.sh":
                owner   => root,
                group   => root,
                mode    => 755,
                ensure  => present,
                source  => 'puppet:///modules/mongodb-tayra-backup/backup_expect.sh',
        }

	#file_line { 'crontab-mongo-tayra-backup':
        # 	path  => '/etc/crontab',
        # 	line  => '0 6 * * * root /usr/local/bin/mongo-tayra-backup.sh -d 3 > /dev/null',
	#}
}
