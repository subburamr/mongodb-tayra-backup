class mongodb-tayra-backup()
{

	file { [ '/data',
         	'/data/backup',
         	'/data/backup/mongodb',
         	'/data/backup/mongodb/archive',
         	'/data/backup/mongodb/full',
		'/data/backup/mongodb/incremental',
		'/opt/tayra', ]:
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
	
	# unzip and place tayra files under /opt/tayra
	file { "/opt/tayra/Tayra-0.8.1.Beta3.zip":
		owner   => root,
        	group   => root,
        	mode    => 644,
        	ensure  => present,
		source  => 'puppet:///modules/mongodb-tayra-backup/Tayra-0.8.1.Beta3.zip',
		notify  => Exec['unzip'],
	}

	exec { "unzip":
  		command     => '/usr/bin/unzip /opt/tayra/Tayra-0.8.1.Beta3.zip -d /opt/tayra',
  		user        => 'root',
  		unless	    => "/usr/bin/test -f /opt/tayra/backup.sh",
  		refreshonly => true,
  		before => File[ '/opt/tayra/backup.sh',	'/opt/tayra/restore.sh', ],
	}

	
	file { "/usr/local/bin/mongo-tayra-backup.sh":
		owner   => root,
        	group   => root,
        	mode    => 755,
        	ensure  => present,
		source  => 'puppet:///modules/mongodb-tayra-backup/mongo-tayra-backup.sh',
	}

	file { [ '/opt/tayra/backup.sh',
		'/opt/tayra/restore.sh', ]:
		require => Exec['unzip'],
		ensure  => present,
		mode => 755,
	}

        file { "/opt/tayra/backup_expect.sh":
                owner   => root,
                group   => root,
                mode    => 755,
                ensure  => present,
                source  => 'puppet:///modules/mongodb-tayra-backup/backup_expect.sh',
        }

        file { '/etc/cron.d/mongodb-tayra-backup-cron':
        	content => template('mongodb-tayra-backup/mongodb-tayra-backup-cron.erb'),
	        owner   => root,
                group   => root,
                mode    => 755,
                ensure  => present,
        }

}
