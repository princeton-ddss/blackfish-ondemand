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
require_relative '../lib/installations'

class LauncherTest < Minitest::Test
  ROOT = Pathname.new(__dir__).parent

  def setup
    @directory = Pathname.new(Dir.mktmpdir('blackfish-launcher'))
    @app = @directory.join('app')
    @stage = @directory.join('session')
    FileUtils.mkdir_p([@app, @stage, @app.join('lib')])
    FileUtils.cp(ROOT.join('lib/installations.rb'), @app.join('lib'))
    FileUtils.cp(ROOT.join('template/launch_helpers.sh'), @stage)
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
    @config = {'default' => '1.0.0a0', 'versions' => {
      '1.0.0a0' => {'executable' => @executable.to_s, 'modules' => []}
    }}
    save_config
    @context = OpenStruct.new(blackfish_version: '1.0.0a0',
      home_dir: @directory.join('private home').to_s, cache_dir: @directory.join('shared cache').to_s)
    FileUtils.mkdir_p(@context.cache_dir)
    @environment = {'ARGUMENTS_FILE' => @stage.join('arguments.json').to_s,
      'START_FILE' => @stage.join('started').to_s, 'USER' => 'test-user'}
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def save_config
    @app.join('installations.yml').write(@config.to_yaml)
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
    session = OpenStruct.new(app: OpenStruct.new(root: @app))
    ERB.new(ROOT.join(file).read, trim_mode: '-').result(binding)
  end

  def prepare_scripts
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
      export host=node.princeton.edu
      source ./before.sh
      bash ./script.sh
    BASH
  end

  def test_repository_catalog_is_valid
    config = BlackfishInstallations.load(ROOT)
    assert config.fetch('versions').key?(config.fetch('default'))
  end

  def test_form_lists_configured_versions_and_home
    @config['versions']['1.0.0'] = Marshal.load(Marshal.dump(@config['versions']['1.0.0a0']))
    save_config
    form = YAML.safe_load(render('form.yml.erb'))
    assert_equal [['1.0.0a0', '1.0.0a0'], ['1.0.0', '1.0.0']], form['attributes']['blackfish_version']['options']
    assert_equal File.join(Dir.home, '.blackfish-ondemand'), form['attributes']['home_dir']['value']
    assert_includes form['form'], 'home_dir'
  end

  def test_arguments_with_spaces_and_shell_metacharacters_are_literal
    @context.home_dir = @directory.join('home $(touch INJECTED); "quote"').to_s
    @context.cache_dir = @directory.join("cache `touch INJECTED` 'quote'").to_s
    FileUtils.mkdir_p(@context.cache_dir)
    output, error, status = launcher
    assert status.success?, "#{output}\n#{error}"
    arguments = JSON.parse(@stage.join('arguments.json').read)
    assert_equal @context.home_dir, arguments[arguments.index('--app-dir') + 1]
    assert_equal @context.home_dir, arguments[arguments.index('--home-dir') + 1]
    assert_equal @context.cache_dir, arguments[arguments.index('--cache-dir') + 1]
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
    assert_equal '/node/node.princeton.edu/8123', server.fetch('BLACKFISH_BASE_PATH')
    assert_equal '0', server.fetch('BLACKFISH_DEBUG')
  end

  def test_init_failure_does_not_start_server
    _, _, status = launcher('INIT_EXIT' => '1')
    refute status.success?
    refute @stage.join('started').exist?
    assert_match(/^Failed:/, @stage.join('launch-status.txt').read)
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
    @context.cache_dir = @directory.join('missing cache').to_s
    _, _, status = launcher
    refute status.success?
    refute @stage.join('arguments.json').exist?
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
    assert_raises(RuntimeError) { BlackfishInstallations.load(@app) }
    @config['versions']['1.0.0a0']['modules'] = ['--help']
    save_config
    assert_raises(RuntimeError) { BlackfishInstallations.load(@app) }
  end

  def test_after_hook_waits_for_http_readiness
    prepare_scripts
    output, error, status = run_shell(<<~'BASH')
      source ./launch_helpers.sh
      SCRIPT_PID=$$
      host=node.princeton.edu
      port=8123
      curl() { printf '%s\n' "$*" > probe.log; }
      clean_up() { exit "$1"; }
      source ./after.sh
    BASH
    assert status.success?, "#{output}\n#{error}"
    assert_includes @stage.join('launch-status.txt').read, 'Ready:'
    assert_includes @stage.join('probe.log').read, 'http://node.princeton.edu:8123/node/node.princeton.edu/8123/login'
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
    assert_includes template.result(view.instance_eval { binding }), 'Starting &lt;Blackfish&gt;'
    view.define_singleton_method(:completed?) { true }
    assert_empty template.result(view.instance_eval { binding }).strip
  end
end
