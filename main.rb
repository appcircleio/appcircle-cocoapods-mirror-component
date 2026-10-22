require 'colored'
require 'uri'

PODFILE_MODES = %w[update fail warn].freeze
SOURCE_LINE = /\A(\s*)source\s+(['"])([^'"]+)\2\s*(#.*)?\z/

def get_env_variable(key)
  ENV[key].nil? || ENV[key] == '' ? nil : ENV[key]
end

def abort_with1(message)
  puts "@@[error] #{message}".red
  exit 1
end

def get_info_msg(message)
  puts " \n#{message.green}"
end

def get_warning_msg(message)
  puts "@@[warning] #{message}".yellow
end

# The URL without user info, for the log.
def shown_url(url)
  url.sub(%r{\A(https?://)[^/@]*@}, '\1')
end

# The public CocoaPods trunk, as a CDN URL or as the old git spec repository.
def public_trunk?(url)
  uri = URI(url)
  uri.host == 'cdn.cocoapods.org' || (uri.host == 'github.com' && uri.path.sub(/\.git\z/, '').chomp('/').casecmp?('/CocoaPods/Specs'))
rescue URI::InvalidURIError
  url == 'trunk'
end

def on_mirror?(url, mirror)
  uri = URI(url)
  mirror_uri = URI(mirror)
  uri.host == mirror_uri.host && "#{uri.path.chomp('/')}/".start_with?(mirror_uri.path)
rescue URI::InvalidURIError
  false
end

# Checks one Podfile. Returns :proxy, :updated, :private or :public.
def check_podfile(path, relative, mirror, mode)
  lines = File.readlines(path, chomp: true)
  sources = lines.each_index.map do |i|
    match = lines[i].match(SOURCE_LINE)
    match && { index: i, indent: match[1], url: match[3] }
  end.compact
  public_sources = sources.select { |s| public_trunk?(s[:url]) || s[:url] == 'trunk' }
  has_mirror = sources.any? { |s| on_mirror?(s[:url], mirror) }

  # Without any source line CocoaPods uses the public trunk.
  implicit_trunk = sources.empty?
  if public_sources.empty? && !implicit_trunk
    if has_mirror
      puts "Podfile: #{relative} already uses the artifact proxy, no change"
      return :proxy
    end
    puts "Podfile: #{relative} uses only #{sources.map { |s| shown_url(s[:url]) }.join(', ')}, not the CocoaPods trunk, no change"
    return :private
  end

  unless mode == 'update'
    found = implicit_trunk ? 'has no source line, so CocoaPods uses https://cdn.cocoapods.org/' : "uses #{public_sources.map { |s| shown_url(s[:url]) }.join(', ')}"
    puts "Podfile: #{relative} #{found}, the public CocoaPods trunk"
    return :public
  end

  if implicit_trunk
    lines.unshift("source '#{mirror}'")
    puts "Podfile: #{relative} updated: added source '#{shown_url(mirror)}' (it had no source line, so CocoaPods used https://cdn.cocoapods.org/) (cloned copy only)"
  else
    # Replace the first public source by the mirror, drop the others (and all of them when the mirror is already there).
    replaced = has_mirror
    public_sources.reverse_each do |s|
      if !replaced && s.equal?(public_sources.first)
        lines[s[:index]] = "#{s[:indent]}source '#{mirror}'"
        replaced = true
      else
        lines.delete_at(s[:index])
      end
    end
    puts "Podfile: #{relative} updated: #{public_sources.map { |s| shown_url(s[:url]) }.join(', ')} -> #{shown_url(mirror)} (cloned copy only)"
  end
  temp = "#{path}.#{Process.pid}.tmp"
  File.write(temp, "#{lines.join("\n")}\n")
  File.rename(temp, path)
  :updated
end

mirror = get_env_variable('AC_MIRROR_COCOAPODS')
if mirror.nil?
  puts 'AC_MIRROR_COCOAPODS is empty: CocoaPods uses the sources of the Podfile.'
  exit 0
end
abort_with1('AC_MIRROR_COCOAPODS must be an http or https URL.') unless mirror.match?(%r{\Ahttps?://[^\s'"]+\z})
mirror += '/' unless mirror.end_with?('/')
mode = (get_env_variable('AC_MIRROR_COCOAPODS_PODFILE') || 'fail').downcase
abort_with1("AC_MIRROR_COCOAPODS_PODFILE must be one of #{PODFILE_MODES.join(', ')}.") unless PODFILE_MODES.include?(mode)

env_file = get_env_variable('AC_ENV_FILE_PATH')
abort_with1('AC_ENV_FILE_PATH is not set.') if env_file.nil?
# Values for the later steps of this build only.
File.open(env_file, 'a') { |f| f.puts('COCOAPODS_DISABLE_STATS=true') }
puts "CocoaPods Mirror: trunk -> #{shown_url(mirror)}"

repository_dir = get_env_variable('AC_REPOSITORY_DIR')
unless repository_dir && Dir.exist?(repository_dir) && !Dir.empty?(repository_dir)
  get_warning_msg('The repository is not cloned yet, so the Podfile check is skipped. Place the CocoaPods Mirror step after Git Clone.')
  exit 0
end

podfiles = Dir.glob(File.join(repository_dir, '**', 'Podfile')).reject { |p| p.match?(%r{/(Pods|node_modules|build|\.git|\.symlinks)/}) }
counts = Hash.new(0)
public_podfiles = []
podfiles.each do |path|
  relative = path.delete_prefix("#{repository_dir}/")
  result = check_podfile(path, relative, mirror, mode)
  counts[result] += 1
  public_podfiles << relative if result == :public
end
if podfiles.empty?
  puts "Podfile (mode: #{mode}): no Podfile in the project"
else
  puts "Podfile (mode: #{mode}): #{podfiles.size} #{podfiles.size == 1 ? 'Podfile' : 'Podfiles'} checked: #{counts[:proxy]} already on the proxy, #{counts[:updated]} updated, #{counts[:private]} with other sources only, #{counts[:public]} still on the CocoaPods trunk"
end

unless public_podfiles.empty?
  message = "#{public_podfiles.join(', ')} uses the public CocoaPods trunk (https://cdn.cocoapods.org/). Add source '#{shown_url(mirror)}' to the Podfile in the project, or set the Podfile Source input to update."
  mode == 'fail' ? abort_with1(message) : get_warning_msg(message)
end
get_info_msg('CocoaPods Mirror is configured.')
