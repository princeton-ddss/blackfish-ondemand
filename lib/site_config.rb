# frozen_string_literal: true

require 'yaml'
require 'pathname'

module BlackfishSiteConfig
  class Error < StandardError; end

  def self.load(root)
    if ENV.key?('BLACKFISH_OOD_CONFIG')
      path = Pathname.new(ENV.fetch('BLACKFISH_OOD_CONFIG'))
      raise Error, 'BLACKFISH_OOD_CONFIG must be an absolute file path' unless path.absolute?
    else
      path = Pathname.new(root).join('config/site.yml')
    end
    validate(YAML.safe_load(path.read))
  rescue Errno::ENOENT
    raise Error, "No site configuration at #{path}. Copy config/site.example.yml to config/site.yml and edit it, or set BLACKFISH_OOD_CONFIG to an absolute configuration path."
  rescue SystemCallError, Psych::Exception => error
    raise Error, "Cannot read site configuration #{path}: #{error.message}"
  rescue KeyError => error
    raise Error, "Site configuration #{path} is missing #{error.key.inspect}"
  end

  def self.validate(config)
    raise Error, 'Site configuration must be a YAML mapping' unless config.is_a?(Hash)
    unknown_keys(config, %w[cluster cache_dir default versions duration_hours])
    cluster = config.fetch('cluster')
    unless cluster.is_a?(String) && !cluster.strip.empty? && !cluster.match?(/[\r\n]/)
      raise Error, 'Configure a nonempty Open OnDemand cluster ID'
    end
    cache_dir = config.fetch('cache_dir')
    unless cache_dir.is_a?(String) && Pathname.new(cache_dir).absolute?
      raise Error, 'Configure an absolute shared cache_dir in the site configuration'
    end
    versions = config.fetch('versions')
    raise Error, 'Configure at least one shared Blackfish installation' unless versions.is_a?(Hash) && !versions.empty?

    versions.each do |version, installation|
      unless version.is_a?(String) && version.match?(/\A[0-9][0-9A-Za-z.+-]*\z/)
        raise Error, "Invalid Blackfish version: #{version.inspect}"
      end
      raise Error, "Invalid installation for Blackfish #{version}" unless installation.is_a?(Hash)
      unknown_keys(installation, %w[executable modules])
      executable = installation.fetch('executable')
      modules = installation.fetch('modules', [])
      unless modules.is_a?(Array) && modules.all? { |name| name.is_a?(String) && !name.empty? && !name.start_with?('-') }
        raise Error, "Invalid module list for Blackfish #{version}"
      end
      unless executable.is_a?(String) && !executable.empty? && !executable.start_with?('-') &&
             (Pathname.new(executable).absolute? || (!modules.empty? && executable == 'blackfish'))
        raise Error, "Blackfish #{version} requires an absolute executable path or a module providing blackfish"
      end
    end
    raise Error, 'Default Blackfish version is not listed in versions' unless versions.key?(config.fetch('default'))

    duration = config.fetch('duration_hours', {})
    raise Error, 'duration_hours must be a YAML mapping' unless duration.is_a?(Hash)
    unknown_keys(duration, %w[default max])
    duration = { 'default' => 1 }.merge(duration)
    unless duration['default'].is_a?(Integer) && duration['default'].positive? &&
           (!duration.key?('max') || (duration['max'].is_a?(Integer) && duration['max'] >= duration['default']))
      raise Error, 'duration_hours.default must be a positive integer and max must be at least the default'
    end
    config.merge('duration_hours' => duration)
  end

  # All ERB files in one job are rendered against the same Session object.
  # Resolve once so a concurrent config edit cannot mix installations/cache paths.
  # Only resolved values are embedded in shell scripts; no config is read on nodes.
  def self.for_session(session, context)
    unless session.instance_variable_defined?(:@blackfish_site_config)
      session.instance_variable_set(:@blackfish_site_config, load(session.app.root))
    end
    config = session.instance_variable_get(:@blackfish_site_config)
    unless context.cluster.to_s == config.fetch('cluster')
      raise Error, 'The selected cluster no longer matches the site configuration; reload the launch form'
    end
    hours = Integer(context.bc_num_hours.to_s, 10)
    maximum = config.fetch('duration_hours')['max']
    unless hours.positive? && (!maximum || hours <= maximum)
      raise Error, 'Requested duration is outside the configured site limits'
    end
    config
  rescue ArgumentError
    raise Error, 'Requested duration must be a positive integer number of hours'
  end

  def self.unknown_keys(mapping, allowed)
    extra = mapping.keys - allowed
    raise Error, "Unknown site configuration keys: #{extra.inspect}" unless extra.empty?
  end
end
