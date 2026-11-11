# frozen_string_literal: true

require 'yaml'
require 'pathname'

module BlackfishInstallations
  def self.load(root)
    config = YAML.safe_load(Pathname.new(root).join('installations.yml').read)
    versions = config.fetch('versions')
    raise 'Configure at least one shared Blackfish installation' unless versions.is_a?(Hash) && !versions.empty?

    versions.each do |version, installation|
      unless version.is_a?(String) && version.match?(/\A[0-9][0-9A-Za-z.+-]*\z/)
        raise "Invalid Blackfish version: #{version.inspect}"
      end
      executable = installation.fetch('executable')
      modules = installation.fetch('modules', [])
      unless modules.is_a?(Array) && modules.all? { |name| name.is_a?(String) && !name.empty? && !name.start_with?('-') }
        raise "Invalid module list for Blackfish #{version}"
      end
      unless executable.is_a?(String) && !executable.empty? && !executable.start_with?('-') &&
             (Pathname.new(executable).absolute? || (!modules.empty? && executable == 'blackfish'))
        raise "Blackfish #{version} requires an absolute executable path or a module providing blackfish"
      end
    end
    raise 'Default Blackfish version is not listed in versions' unless versions.key?(config.fetch('default'))

    config
  end
end
