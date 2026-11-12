require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'ostruct'
require 'erb'
require 'json'
require 'yaml'
require 'open3'
require 'shellwords'
require_relative '../lib/site_config'

class LauncherTest < Minitest::Test
  ROOT = Pathname.new(__dir__).parent

  def setup
    @previous_site_env = ENV.delete('BLACKFISH_OOD_CONFIG')
    @directory = Pathname.new(Dir.mktmpdir('blackfish-launcher'))
    @app = @directory.join('app')
    @stage = @directory.join('session')
    FileUtils.mkdir_p([@app, @stage, @app.join('lib'), @app.join('config')])
    FileUtils.cp(ROOT.join('lib/site_config.rb'), @app.join('lib'))
    FileUtils.cp(ROOT.join('template/launch_helpers.sh'), @stage)
    FileUtils.cp(ROOT.join('template/prepare_profile.py'), @stage)
    @executable = @directory.join('shared installation/blackfish')
    FileUtils.mkdir_p(@executable.dirname)
    @executable.write(<<~'RUBY')
      #!/usr/bin/env ruby
      require 'json'
      case ARGV.first
      when 'version'
        puts "blackfish-ai #{ENV.fetch('ACTUAL_VERSION', '1.0.0a0')}"
      when 'init'
        File.write(ENV.fetch('ARGUMENTS_FILE'), JSON.generate(ARGV))
        exit ENV.fetch('INIT_EXIT', '0').to_i
      when 'profile'
        exit ENV.fetch('PROFILE_EXIT', '0').to_i
      when 'start'
        File.write(ENV.fetch('START_FILE'), ENV.fetch('BLACKFISH_HOME_DIR'))
        File.write('server-environment.json', JSON.generate(ENV.to_h.select { |key, _| %w[BLACKFISH_HOST BLACKFISH_PORT BLACKFISH_BASE_PATH BLACKFISH_DEBUG].include?(key) }))
        exit ENV.fetch('START_EXIT', '0').to_i
      else
        abort "Unexpected command: #{ARGV.inspect}"
      end
    RUBY
    @executable.chmod(0755)
    @cache = @directory.join('shared cache')
    @config = {'cluster' => 'example-cluster', 'cache_dir' => @cache.to_s, 'default' => '1.0.0a0', 'versions' => {
      '1.0.0a0' => {'executable' => @executable.to_s, 'modules' => []}
    }}
    save_config
    @context = OpenStruct.new(cluster: 'example-cluster', bc_num_hours: '1', blackfish_version: '1.0.0a0',
      home_dir: @directory.join('private home').to_s)
    FileUtils.mkdir_p(@cache)
    @environment = {'ARGUMENTS_FILE' => @stage.join('arguments.json').to_s,
      'START_FILE' => @stage.join('started').to_s, 'USER' => 'test-user'}
  end

  def teardown
    ENV.delete('BLACKFISH_OOD_CONFIG')
    ENV['BLACKFISH_OOD_CONFIG'] = @previous_site_env if @previous_site_env
    FileUtils.remove_entry(@directory)
  end

  def save_config
    @app.join('config/site.yml').write(@config.to_yaml)
  end

  def render(file)
    # Open OnDemand sets the template filename and renders forms with no binding.
    # Do not leak test locals (such as root/session/context) into that context.
    if file == 'form.yml.erb'
      template = ERB.new(ROOT.join(file).read, trim_mode: '-')
      template.filename = @app.join('form.yml.erb').to_s
      return template.result(nil)
    end
    context = @context
    session = (@session ||= OpenStruct.new(app: OpenStruct.new(root: @app)))
    ERB.new(ROOT.join(file).read, trim_mode: '-').result(binding)
  end

  def prepare_scripts
    @session = OpenStruct.new(app: OpenStruct.new(root: @app))
    %w[before script after].each do |name|
      @stage.join("#{name}.sh").write(render("template/#{name}.sh.erb"))
    end
  end

  def run_shell(script, environment = {})
    Open3.capture3(@environment.merge(environment), 'bash', '-c', script, chdir: @stage.to_s)
  end

  def launcher(environment = {})
    prepare_scripts
    run_shell(<<~'BASH', environment)
      find_port() { echo 8123; }
      create_passwd() { printf '%032d' 0; }
      export host=node.example.edu
      source ./before.sh
      bash ./script.sh
    BASH
  end

  def wrapped_launcher(environment = {})
    prepare_scripts
    run_shell(<<~'BASH', environment)
      find_port() { echo 8123; }
      create_passwd() { printf '%032d' 0; }
      export host=node.example.edu
      source ./before.sh
      bash ./script.sh &
      SCRIPT_PID=$!
      curl() { return 1; }
      sleep() { command sleep 0.02; }
      clean_up() { wait "$SCRIPT_PID" 2>/dev/null || :; exit "$1"; }
      source ./after.sh
    BASH
  end

  def failure_messages
    @stage.join('launch-status.txt').read.lines.select { |line| line.include?('] Failed:') }
  end

  def test_repository_catalog_is_valid
    config = BlackfishSiteConfig.validate(YAML.safe_load(ROOT.join('config/site.example.yml').read))
    assert config.fetch('versions').key?(config.fetch('default'))
  end

  def test_staged_scripts_use_one_snapshot_and_need_no_site_file_on_nodes
    original_cache = @config.fetch('cache_dir')
    before = render('template/before.sh.erb')
    @config['cache_dir'] = @directory.join('changed cache').to_s
    save_config
    @app.join('config/site.yml').delete
    ENV['BLACKFISH_OOD_CONFIG'] = '/unavailable/on/compute/nodes.yml'
    script = render('template/script.sh.erb')
    assert_includes script, Shellwords.escape(original_cache)
    refute_includes script, Shellwords.escape(@config.fetch('cache_dir'))
    @stage.join('before.sh').write(before)
    @stage.join('script.sh').write(script)
    output, error, status = run_shell(<<~'BASH', 'BLACKFISH_OOD_CONFIG' => '/unavailable/on/compute/nodes.yml')
      find_port() { echo 8123; }
      create_passwd() { printf '%032d' 0; }
      export host=node.example.edu
      source ./before.sh
      bash ./script.sh
    BASH
    assert status.success?, "#{output}\n#{error}"
    assert_equal original_cache, read_profiles.fetch('Default').fetch('cache_dir')
  end

  def test_form_uses_configured_cluster_and_duration
    @config['cluster'] = 'gpu-cluster'
    @config['duration_hours'] = {'default' => 2, 'max' => 6}
    save_config
    form = YAML.safe_load(render('form.yml.erb'))
    assert_equal 'gpu-cluster', form.fetch('cluster')
    assert_equal 2, form['attributes']['bc_num_hours']['value']
    assert_equal 6, form['attributes']['bc_num_hours']['max']
  end

  def test_form_lists_configured_versions_and_home
    @config['versions']['1.0.0'] = Marshal.load(Marshal.dump(@config['versions']['1.0.0a0']))
    save_config
    form = YAML.safe_load(render('form.yml.erb'))
    assert_equal [['1.0.0a0', '1.0.0a0'], ['1.0.0', '1.0.0']], form['attributes']['blackfish_version']['options']
    assert_equal File.join(Dir.home, '.blackfish'), form['attributes']['home_dir']['value']
    assert_includes form['form'], 'home_dir'
    refute_includes form['form'], 'cache_dir'
    refute form['attributes'].key?('cache_dir')
  end

  def test_arguments_with_spaces_and_shell_metacharacters_are_literal
    @context.home_dir = @directory.join('home $(touch INJECTED); "quote"').to_s
    @config['cache_dir'] = @directory.join("cache `touch INJECTED` 'quote' %value").to_s
    FileUtils.mkdir_p(@config['cache_dir'])
    save_config
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    arguments = JSON.parse(@stage.join('arguments.json').read)
    assert_equal @context.home_dir, arguments[arguments.index('--app-dir') + 1]
    assert_equal @context.home_dir, read_profiles.fetch('Default').fetch('home_dir')
    assert_equal @config.fetch('cache_dir'), read_profiles.fetch('Default').fetch('cache_dir')
    assert_equal @context.home_dir, @stage.join('started').read
    refute @stage.join('INJECTED').exist?
    refute_includes output + error, '00000000000000000000000000000000'
  end

  def test_server_binds_all_interfaces_without_changing_proxy_path
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    server = JSON.parse(@stage.join('server-environment.json').read)
    assert_equal '0.0.0.0', server.fetch('BLACKFISH_HOST')
    assert_equal '8123', server.fetch('BLACKFISH_PORT')
    assert_equal '/node/node.example.edu/8123', server.fetch('BLACKFISH_BASE_PATH')
    assert_equal '0', server.fetch('BLACKFISH_DEBUG')
  end

  def test_init_failure_does_not_start_server
    _, _, status = launcher('INIT_EXIT' => '1')
    refute status.success?
    refute @stage.join('started').exist?
    assert_match(/^\[.*\] Failed:/, @stage.join('launch-status.txt').read)
  end

  def test_profile_setup_failure_despite_successful_init_does_not_start_server
    _, _, status = launcher('PROFILE_EXIT' => '1')
    refute status.success?
    refute @stage.join('started').exist?
    assert_includes @stage.join('launch-status.txt').read, 'No usable default profile'
  end

  def test_wrong_installed_version_fails_before_initialization
    _, _, status = launcher('ACTUAL_VERSION' => '0.5.0')
    refute status.success?
    refute @stage.join('arguments.json').exist?
  end

  def test_missing_shared_executable_fails_before_initialization
    @config['versions']['1.0.0a0']['executable'] = '/nonexistent/blackfish'
    save_config
    _, _, status = launcher
    refute status.success?
    refute @stage.join('arguments.json').exist?
    assert_includes @stage.join('launch-status.txt').read, 'unavailable'
  end

  def test_unavailable_version_is_rejected_during_rendering
    @context.blackfish_version = '1.2.3; touch INJECTED'
    assert_raises(RuntimeError) { render('template/before.sh.erb') }
  end

  def test_relative_home_is_rejected
    @context.home_dir = 'relative/home'
    _, _, status = launcher
    refute status.success?
    refute @stage.join('arguments.json').exist?
  end

  def test_nonexistent_cache_is_rejected
    @config['cache_dir'] = @directory.join('missing cache').to_s
    save_config
    _, _, status = launcher
    refute status.success?
    refute @stage.join('arguments.json').exist?
  end

  def read_profiles
    script = "import configparser,json,sys; p=configparser.ConfigParser(); p.read(sys.argv[1]); print(json.dumps({s:dict(p[s]) for s in p.sections()}))"
    output, error, status = Open3.capture3('python3', '-c', script, File.join(@context.home_dir, 'profiles.cfg'))
    assert status.success?, error
    JSON.parse(output)
  end

  def write_profiles(contents)
    FileUtils.mkdir_p(@context.home_dir)
    Pathname.new(@context.home_dir).join('profiles.cfg').write(contents)
  end

  def test_fresh_home_creates_only_the_initial_profile
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    profiles = read_profiles
    assert_equal ['Default'], profiles.keys
    assert_equal 'true', profiles.fetch('Default').fetch('default')
    assert_equal 'slurm', profiles.fetch('Default').fetch('schema')
    assert_equal 'localhost', profiles.fetch('Default').fetch('host')
    assert_equal 'test-user', profiles.fetch('Default').fetch('user')
    assert_equal @config.fetch('cache_dir'), profiles.fetch('Default').fetch('cache_dir')
    assert_equal 0600, File.stat(File.join(@context.home_dir, 'profiles.cfg')).mode & 0777
  end

  def test_existing_explicit_default_and_configuration_are_preserved
    existing = "; user comments\n[research]\nschema = local\nhome_dir = /custom\ncache_dir = /custom/cache\ndefault = yes\n"
    write_profiles(existing)
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    assert_equal existing, File.read(File.join(@context.home_dir, 'profiles.cfg'))
    profiles = read_profiles
    assert_equal 'yes', profiles.fetch('research').fetch('default')
    refute profiles.key?('Default')
    assert_equal '/custom/cache', profiles.fetch('research').fetch('cache_dir')
  end

  def test_legacy_default_without_flag_is_preserved
    write_profiles("[default]\nschema = local\nhome_dir = /custom\ncache_dir = /custom/cache\n")
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    profiles = read_profiles
    assert_equal ['default'], profiles.keys
    refute profiles.fetch('default').key?('default')
    refute profiles.key?('Default')
  end

  def test_first_profile_fallback_without_flag_is_preserved
    write_profiles("[research]\nschema = local\nhome_dir = /custom\ncache_dir = /custom/cache\n")
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    profiles = read_profiles
    assert_equal ['research'], profiles.keys
    refute profiles.key?('Default')
  end

  def test_existing_ondemand_profile_is_not_rewritten_or_revalidated_against_admin_cache
    existing = "[ondemand]\nschema = slurm\nhost = localhost\nuser = test-user\nhome_dir = /different/home\ncache_dir = /different/cache\ndefault = true\n"
    write_profiles(existing)
    @config['cache_dir'] = @directory.join('unavailable admin cache').to_s
    save_config
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    assert_equal existing, File.read(File.join(@context.home_dir, 'profiles.cfg'))
    assert @stage.join('started').exist?
  end

  def test_existing_custom_profile_skips_admin_cache_validation_and_adds_nothing
    existing = "[research]\nschema = local\nhome_dir = /custom\ncache_dir = /custom/cache\ndefault = true\n"
    write_profiles(existing)
    @config['cache_dir'] = @directory.join('missing admin cache').to_s
    save_config
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    assert_equal existing, File.read(File.join(@context.home_dir, 'profiles.cfg'))
    assert_equal ['research'], read_profiles.keys
  end

  def test_comments_without_profiles_create_initial_profile
    existing = "; first launch\n"
    write_profiles(existing)
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    assert File.read(File.join(@context.home_dir, 'profiles.cfg')).start_with?(existing)
    assert_equal ['Default'], read_profiles.keys
  end

  def test_repeated_launch_does_not_duplicate_initial_profile
    _, _, status = launcher
    assert status.success?
    existing = File.read(File.join(@context.home_dir, 'profiles.cfg'))
    _, _, status = launcher
    assert status.success?
    assert_equal existing, File.read(File.join(@context.home_dir, 'profiles.cfg'))
  end

  def test_malformed_existing_profiles_fail_without_overwriting
    existing = "not an INI file\n"
    write_profiles(existing)
    _, _, status = launcher
    refute status.success?
    assert_equal existing, File.read(File.join(@context.home_dir, 'profiles.cfg'))
    refute @stage.join('started').exist?
  end

  def test_wrapper_retains_specific_admin_cache_failure_once
    @config['cache_dir'] = @directory.join('misspecified admin cache').to_s
    save_config
    _, _, status = wrapped_launcher
    refute status.success?
    assert_equal 1, failure_messages.length
    assert_includes failure_messages.first, "Cannot create Default: the administrator's cache directory is missing or unreadable"
    assert_includes failure_messages.first, @config.fetch('cache_dir')
    refute @stage.join('started').exist?
  end

  def test_wrapper_retains_default_profile_validation_failure_once
    existing = "[research]\nschema = unknown\ndefault = true\n"
    write_profiles(existing)
    _, _, status = wrapped_launcher('PROFILE_EXIT' => '1')
    refute status.success?
    assert_equal 1, failure_messages.length
    assert_includes failure_messages.first, 'No usable default profile is available'
    assert_equal existing, File.read(File.join(@context.home_dir, 'profiles.cfg'))
    refute @stage.join('started').exist?
  end

  def test_wrapper_retains_initialization_failure_once
    _, _, status = wrapped_launcher('INIT_EXIT' => '1')
    refute status.success?
    assert_equal 1, failure_messages.length
    assert_includes failure_messages.first, 'Could not initialize Blackfish application data'
    refute @stage.join('started').exist?
  end

  def test_wrapper_retains_server_failure_once
    _, _, status = wrapped_launcher('START_EXIT' => '1')
    refute status.success?
    assert_equal 1, failure_messages.length
    assert_includes failure_messages.first, 'Blackfish server exited with an error'
  end

  def test_after_hook_stops_on_recorded_failure_even_before_process_exits
    prepare_scripts
    _, _, status = run_shell(<<~'BASH')
      source ./launch_helpers.sh
      launch_error 'Original setup error'
      SCRIPT_PID=$$
      curl() { touch unexpected-probe; return 0; }
      clean_up() { exit "$1"; }
      source ./after.sh
    BASH
    refute status.success?
    assert_equal 1, failure_messages.length
    assert_includes failure_messages.first, 'Original setup error'
    refute @stage.join('unexpected-probe').exist?
    refute_includes @stage.join('launch-status.txt').read, 'Ready!'
  end

  def test_relative_admin_cache_is_rejected_during_staging
    @config['cache_dir'] = 'relative/cache'
    save_config
    assert_raises(BlackfishSiteConfig::Error) { prepare_scripts }
  end

  def test_modules_are_loaded_before_executable_is_used
    @config['versions']['1.0.0a0']['modules'] = ['blackfish/1.0.0a0']
    save_config
    prepare_scripts
    output, error, status = run_shell(<<~'BASH')
      module() { printf '%s\n' "$*" >> modules.log; }
      find_port() { echo 8123; }
      create_passwd() { printf '%032d' 0; }
      source ./before.sh
    BASH
    assert status.success?, "#{output}\n#{error}"
    assert_equal "purge\nload blackfish/1.0.0a0\n", @stage.join('modules.log').read
  end

  def test_invalid_catalog_entries_are_rejected
    @config['versions']['1.0.0a0']['executable'] = 'blackfish'
    save_config
    assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@app) }
    @config['versions']['1.0.0a0']['modules'] = ['--help']
    save_config
    assert_raises(BlackfishSiteConfig::Error) { BlackfishSiteConfig.load(@app) }
  end

  def test_after_hook_waits_for_http_readiness
    prepare_scripts
    output, error, status = run_shell(<<~'BASH')
      source ./launch_helpers.sh
      SCRIPT_PID=$$
      host=node.example.edu
      port=8123
      curl() { printf '%s\n' "$*" > probe.log; }
      clean_up() { exit "$1"; }
      source ./after.sh
    BASH
    assert status.success?, "#{output}\n#{error}"
    assert_includes @stage.join('launch-status.txt').read, 'Ready!'
    assert_includes @stage.join('probe.log').read, 'http://node.example.edu:8123/node/node.example.edu/8123/login'
  end

  def test_after_hook_detects_early_exit
    prepare_scripts
    _, _, status = run_shell(<<~'BASH')
      source ./launch_helpers.sh
      SCRIPT_PID=99999999
      clean_up() { exit "$1"; }
      source ./after.sh
    BASH
    refute status.success?
    assert_includes @stage.join('launch-status.txt').read, 'exited before becoming ready'
  end

  def test_after_hook_times_out_without_publishing_readiness
    prepare_scripts
    _, _, status = run_shell(<<~'BASH')
      source ./launch_helpers.sh
      SCRIPT_PID=$$
      curl() { return 1; }
      sleep() { SECONDS=$((SECONDS + 120)); }
      clean_up() { exit "$1"; }
      source ./after.sh
    BASH
    refute status.success?
    assert_includes @stage.join('launch-status.txt').read, 'did not respond within 120 seconds'
  end

  def test_shell_templates_parse
    prepare_scripts
    %w[before script after].each do |name|
      _, error, status = Open3.capture3('bash', '-n', @stage.join("#{name}.sh").to_s)
      assert status.success?, error
    end
  end

  def test_launch_status_preserves_timestamped_history_and_matches_output
    output, error, status = run_shell(<<~'BASH')
      source ./launch_helpers.sh
      launch_status 'Preparing data'
      launch_status 'Starting server'
      launch_status 'Ready!'
    BASH
    assert status.success?, error
    lines = @stage.join('launch-status.txt').read.lines
    assert_equal 3, lines.length
    assert_match(/\A\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Preparing data\n/, lines.first)
    assert_includes lines[1], 'Starting server'
    assert_includes lines.last, 'Ready!'
    assert_equal output, lines.join
  end

  def test_completed_card_preserves_recent_log_lines_and_escapes_them
    staged_root = @stage
    lines = (1..45).map { |number| "[2026-11-11 15:41:18] Step #{number} <Blackfish>\n" }
    stage_log = @stage.join('launch-status.txt')
    stage_log.write(lines.join)
    html = ERB.new(ROOT.join('completed.html.erb').read).result(binding)
    refute_includes html, 'Step 5 '
    assert_includes html, 'Step 6 &lt;Blackfish&gt;'
    assert_includes html, 'Step 45 &lt;Blackfish&gt;'
    refute_includes html, '<Blackfish>'
  end

  def test_status_html_is_escaped
    staged_root = @stage
    @stage.join('launch-status.txt').write('<script>alert(1)</script>')
    html = ERB.new(ROOT.join('completed.html.erb').read).result(binding)
    refute_includes html, '<script>'
    assert_includes html, '&lt;script&gt;'
  end

  def test_launch_status_card_renders_queued_and_starting_states
    stage = @stage
    view = Object.new
    view.define_singleton_method(:staged_root) { stage }
    view.define_singleton_method(:completed?) { false }
    view.define_singleton_method(:queued?) { true }
    template = ERB.new(ROOT.join('info.html.erb').read)
    assert_includes template.result(view.instance_eval { binding }), 'Waiting for a cluster node'
    view.define_singleton_method(:queued?) { false }
    stage.join('launch-status.txt').write('Starting <Blackfish>')
    html = template.result(view.instance_eval { binding })
    assert_includes html, 'Starting &lt;Blackfish&gt;'
    refute_includes html, 'Refresh this page'
    assert_includes html, 'role="log"'
    view.define_singleton_method(:completed?) { true }
    assert_empty template.result(view.instance_eval { binding }).strip
  end
end
