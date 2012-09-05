class OperatingSystemNotSupportedError < StandardError ; end

module KnifeSolo
  module Bootstraps
    class OperatingSystemNotImplementedError < StandardError
    end

    def self.class_exists_for?(os_name)
      begin
        true if self.class_for_operating_system(os_name).class == Class
      rescue => exception
        false
      end
    end

    def self.class_for_operating_system(os_name)
      begin
        os_class_name = os_name.gsub(/\s/,'')
        eval("KnifeSolo::Bootstraps::#{os_class_name}")
      rescue
        raise OperatingSystemNotImplementedError.new("#{os_name} not implemented.  Feel free to add a bootstrap implementation in KnifeSolo::Bootstraps::#{os_class_name}")
      end
    end

    module Delegates
      def stream_command(cmd)
        prepare.stream_command(cmd)
      end

      def run_command(cmd)
        prepare.run_command(cmd)
      end

      def ui
        prepare.ui
      end

      def prepare
        @prepare
      end
    end #Delegates

    module InstallCommands

      def bootstrap!
        run_pre_bootstrap_checks()
        send("#{distro[:type]}_install")
      end

      def distro
        raise "implement distro detection for #{self.class.name}"
      end

      def gem_packages
        raise "implement gem packages for #{self.class.name}"
      end

      def http_client_get_url(url, file)
        stream_command <<-BASH
          if which curl 2>/dev/null; then
            curl -L -o #{file} #{url}
          else
            wget -O #{file} #{url}
          fi
        BASH
      end

      def omnibus_install
        url = prepare.config[:omnibus_url] || "http://opscode.com/chef/install.sh"
        file = File.basename(url)
        http_client_get_url(url, file)
        # `release_version` within install.sh will be installed if
        # `omnibus_version` is not provided.
        install_command = "sudo bash #{file}"
        install_command << " -v #{prepare.config[:omnibus_version]}" if prepare.config[:omnibus_version]
        install_command << " #{prepare.config[:options]}" if prepare.config[:options]

        stream_command(install_command)
      end

      def ubuntu_omnibus_install
        omnibus_install
        # Update to avoid out-of-date package caches
        run_command("sudo apt-get update")
        # Make sure we have rsync on builds that don't include it by default
        # (observed on linode's ubuntu 10.04 images)
        run_command("sudo apt-get install rsync")
      end

      def gem_install
        ui.msg "Installing rubygems from source..."
        release = "rubygems-1.8.10"
        file = "#{release}.tgz"
        url = "http://production.cf.rubygems.org/rubygems/#{file}"
        http_client_get_url(url)
        run_command("tar zxf #{file}")
        run_command("cd #{release} && sudo ruby setup.rb --no-format-executable")
        run_command("sudo rm -rf #{release} #{file}")
        run_command("sudo gem install --no-rdoc --no-ri #{gem_packages().join(' ')}")
      end
    end #InstallCommands

    class Base
      include KnifeSolo::Bootstraps::Delegates
      include KnifeSolo::Bootstraps::InstallCommands

      def initialize(prepare)
        # instance of Chef::Knife::Prepare
        @prepare = prepare
      end

      def run_pre_bootstrap_checks ; end
      # run right before we run #{distro[:type]}_install method
      # barf out here if need be
    end

  end # Bootstraps
end


# bootstrap classes for different OSes
Dir[File.dirname(__FILE__) + '/bootstraps/*.rb'].each {|p| require p}
