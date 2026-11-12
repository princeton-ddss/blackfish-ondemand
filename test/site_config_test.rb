require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'ostruct'
require 'yaml'
require_relative '../lib/site_config'

class SiteConfigTest < Minitest::Test
  ROOT = Pathname.new(__dir__).parent

  def setup
    @previous_env = ENV.delete('BLACKFISH_OOD_CONFIG')
    @root = Pathname.new(Dir.mktmpdir('blackfish-site'))
    @root.join('config').mkpath
    @config = YAML.safe_load(ROOT.join('config/site.example.yml').read)
    save
  end

  def teardown
    ENV.delete('BLACKFISH_OOD_CONFIG')
    ENV['BLACKFISH_OOD_CONFIG'] = @previous_env if @previous_env
    FileUtils.remove_entry(@root)
  end

  def save
    @root.join('config/site.yml').write(@config.to_yaml)
  end

  def test_explicit_path_overrides_local_config
    external = @root.join('external.yml')
    external.write(ROOT.join('test/fixtures/module-site.yml').read)
    ENV['BLACKFISH_OOD_CONFIG'] = external.to_s
    config = BlackfishSiteConfig.load(@root)
    assert_equal 'gpu-cluster', config.fetch('cluster')
    assert_equal 'blackfish', config.fetch('versions').fetch('2.0.0').fetch('executable')
  end

  def test_missing_explicit_path_does_not_fall_back
    ENV['BLACKFISH_OOD_CONFIG'] = @root.join('missing.yml').to_s
    error = assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@root) }
    assert_includes error.message, 'No site configuration'
  end

  def test_unconfigured_checkout_has_an_actionable_error
    @root.join('config/site.yml').delete
    error = assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@root) }
    assert_includes error.message, 'config/site.example.yml'
    assert_includes error.message, 'BLACKFISH_OOD_CONFIG'
  end

  def test_relative_or_empty_override_is_rejected
    ['', 'relative/site.yml'].each do |path|
      ENV['BLACKFISH_OOD_CONFIG'] = path
      assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@root) }
    end
  end

  def test_both_documented_examples_validate_without_probing_installations
    %w[config/site.example.yml config/examples/princeton-della.yml test/fixtures/module-site.yml].each do |path|
      config = BlackfishSiteConfig.validate(YAML.safe_load(ROOT.join(path).read))
      assert config.fetch('versions').key?(config.fetch('default'))
    end
  end

  def test_generic_duration_default_has_no_site_limit
    @config.delete('duration_hours')
    save
    assert_equal({'default' => 1}, BlackfishSiteConfig.load(@root).fetch('duration_hours'))
  end

  def test_missing_required_fields_and_typos_are_rejected
    %w[cluster cache_dir default versions].each do |key|
      config = @config.reject { |candidate, _| candidate == key }
      @root.join('config/site.yml').write(config.to_yaml)
      assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@root) }
    end
    @config['cache_dri'] = '/a/typo'
    save
    assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@root) }
  end

  def test_malformed_yaml_and_wrong_types_are_rejected
    ["versions: [", "---\n- not a mapping", "---\n"].each do |contents|
      @root.join('config/site.yml').write(contents)
      assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@root) }
    end
  end

  def test_invalid_duration_limits_are_rejected
    [{'default' => 0}, {'default' => '2'}, {'default' => 3, 'max' => 2}, {'max' => false}].each do |duration|
      @config['duration_hours'] = duration
      save
      assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@root) }
    end
  end

  def test_submission_rejects_cached_cluster_and_excessive_duration
    session = OpenStruct.new(app: OpenStruct.new(root: @root))
    context = OpenStruct.new(cluster: 'old-cluster', bc_num_hours: '1')
    assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.for_session(session, context) }
    context.cluster = 'example-cluster'
    %w[0 9 invalid].each do |hours|
      context.bc_num_hours = hours
      assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.for_session(session, context) }
    end
    context.bc_num_hours = '8'
    assert_equal 'example-cluster', BlackfishSiteConfig.for_session(session, context).fetch('cluster')
  end

  def test_new_sessions_pick_up_site_changes
    context = OpenStruct.new(cluster: 'example-cluster', bc_num_hours: '1')
    first = OpenStruct.new(app: OpenStruct.new(root: @root))
    assert_equal '/shared/blackfish/cache', BlackfishSiteConfig.for_session(first, context).fetch('cache_dir')
    @config['cache_dir'] = '/different/shared/cache'
    save
    second = OpenStruct.new(app: OpenStruct.new(root: @root))
    assert_equal '/different/shared/cache', BlackfishSiteConfig.for_session(second, context).fetch('cache_dir')
    assert_equal '/shared/blackfish/cache', BlackfishSiteConfig.for_session(first, context).fetch('cache_dir')
  end
end
