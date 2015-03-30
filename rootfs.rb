require_relative 'imageconfig'

require 'open-uri'
require 'digest'


class RootFS
  def initialize(config)
    @c = config
    @dev = %w(sys proc dev)
    system('sudo apt-get install qemu-user-static')
  end

  def install(d)
    @target = d
    Dir.mkdir('cache') unless Dir.exist?('cache')

    puts 'Downloading the rootfs'
    # FIXME: Assume tar.gz format for now
    unless checksum_matches?
      File.write('cache/rootfs.tar.gz', open(@c.config[:rootfs][:url]).read)
      fail 'Checksum failed to match' unless checksum_matches?
    end

    system("sudo tar xf cache/rootfs.tar.gz -C #{@target}")
    fail 'Could not untar the rootfs!' unless $?.success?

    begin
      mount
      configure
    ensure
      unmount
    end
  end

  def checksum_matches?
    return true if @c.config[:rootfs][:md5sum].nil?
    sum = Digest::MD5.file('cache/rootfs.tar.gz').hexdigest
    @c.config[:rootfs][:md5sum] == sum
  end

  def mount
    system("sudo cp /usr/bin/qemu-arm-static #{@target}/usr/bin/")
    @dev.each do |d|
      system('sudo', 'mount', '--bind', "/#{d}", "#{@target}/#{d}")
    end
  end

  def unmount
    @dev.each do |d|
      system('sudo',  'umount', "#{@target}/#{d}")
    end
    system("sudo rm #{@target}/usr/bin/qemu-arm-static")
  end

  def configure
    configure_login if @c.config.keys.include? :login
  end

  def configure_login
    puts "Adding user #{@c.config[:login][:username]}"
    system("sudo chroot #{@target} useradd #{@c.config[:login][:username]}")
    fail 'Could not add the user!' unless $?.success?

    puts 'Setting the password'
    # Mental password command
    pswdcmd = "sh -c \"echo \"#{@c.config[:login][:password]}:#{@c.config[:login][:username]}\" | chpasswd\""
    system("sudo chroot #{@target} #{pswdcmd}")
    fail 'Could not add the user!' unless $?.success?

    @c.config[:login][:groups].each do |g|
      puts "Adding user to #{g} group"
      system("sudo chroot #{@target} usermod -a -G #{g} #{@c.config[:login][:username]}")
      fail 'Could not add the user to the #{g} group!' unless $?.success?
    end
  end
end
