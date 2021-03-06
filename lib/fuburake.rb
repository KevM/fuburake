include FileUtils
include FileTest

require_relative 'nunit'
require_relative 'msbuild'
require_relative 'nuget'
require_relative 'platform'
require_relative 'ripple'
require_relative 'assembly_info'
require_relative 'bottles'

load "VERSION.txt"

module FubuRake
  class SolutionTasks
	attr_accessor :clean, 
		:compile, 
		:assembly_info,
		:ripple_enabled, 
		:fubudocs_enabled, 
		:options, 
		:defaults,
		:ci_steps,
		:precompile,
		:integration_test,
		:compilations
		
		
		
	def compile_step(name, solution)
		@compilations ||= []
	
		@compilations << CompileTarget.new(name, solution)
	end
	
	def assembly_bottle(project)
		@compilations ||= []
	
		@compilations << FubuRake::AssemblyBottle.new(project)
	end
  end
  
  class Solution
	attr_accessor :options, :compilemode, :build_number
  
    def initialize(&block)
	  tasks = SolutionTasks.new
	  block.call(tasks)

	  @defaultTask = create_task(:default, "**Default**, compiles and runs tests")
	  @ciTask = create_task(:ci,  "Target used for the CI server")
	  @ciTask.enhance [:default]
	  
	  options = tasks.options
	  options ||= {}
	  
	  tc_build_number = ENV["BUILD_NUMBER"]
	  build_revision = tc_build_number || Time.new.strftime('5%H%M')
	  asm_version = BUILD_VERSION + ".0"
	  @build_number = "#{BUILD_VERSION}.#{build_revision}"
	  
	  # SAMPLE: fuburake-options
	  @options = {
		:compilemode => ENV['config'].nil? ? "Debug" : ENV['config'],
		:clrversion => 'v4.0.30319',
		:platform => 'x86',
		:unit_test_list_file => 'TESTS.txt',
		:unit_test_projects => [],
		:build_number => @build_number,
		:asm_version => asm_version,
		:tc_build_number => tc_build_number,
		:build_revision => build_revision,
		:source => 'src'}.merge(options)
	  # ENDSAMPLE
		
	  @compilemode = @options[:compilemode]
		
	  tasks.clean ||= []
	  tasks.defaults ||= []
	  tasks.ci_steps ||= []
	  tasks.precompile ||= []
	  

	  enable_docs tasks
	  FubuRake::AssemblyInfo.create tasks, @options
	  FubuRake::Ripple.create tasks, @options
	  make_clean tasks
	  FubuRake::MSBuild.create_task tasks, @options
	  FubuRake::NUnit.create_task tasks, @options

	  add_dependency :compile, [:clean, :version, 'ripple:restore', 'docs:bottle']

	  Rake::Task[:compile].enhance(tasks.precompile)
	  add_dependency :unit_test, :compile
	  add_dependency :default, [:compile, :unit_test]
	  add_dependency :default, :unit_test
	  Rake::Task[:default].enhance tasks.defaults
	  Rake::Task[:ci].enhance tasks.ci_steps
	  add_dependency :ci, tasks.ci_steps
	  add_dependency :ci, ["ripple:history", "ripple:package"]

	  tasks.compilations ||= []
	  tasks.compilations.each do |c|
		c.create @options
	  end
	end
	
	def add_dependency(from, to)
	  if to.kind_of?(Array)
	    to.each do |dep|
		  add_dependency from, dep
		end
	  end
	
	  if !Rake::Task.task_defined?(from)
	    return
	  end
	  
	  if !Rake::Task.task_defined?(to)
	    return
	  end 
	  
	  Rake::Task[from].enhance [to]
	end
	
	def create_task(name, description)
	  task = Rake::Task.define_task name do
	  
	  end
	  task.add_description description
	  
	  return task
	end

	def make_clean(tasks)
	  if tasks.clean.any?
	    @cleanTask = Rake::Task.define_task :clean do
		  tasks.clean.each do |dir|
			cleanDirectory dir
		  end
		end
	  
		@cleanTask.add_description "Prepares the working directory for a new build"
	  end
	end


	def enable_docs(tasks)
	  if tasks.fubudocs_enabled
		if Platform.is_nix
			Dir.glob('**/*.Docs.csproj').each do |f|
				tasks.assembly_bottle File.basename(f, ".csproj")
			end
		else
			require_relative 'fubudocs'
		end
	  
		
	  end
	end
  end
end




def copyOutputFiles(fromDir, filePattern, outDir)
  Dir.glob(File.join(fromDir, filePattern)){|file| 		
	copy(file, outDir) if File.file?(file)
  } 
end

def waitfor(&block)
  checks = 0
  until block.call || checks >10 
    sleep 0.5
    checks += 1
  end
  raise 'waitfor timeout expired' if checks > 10
end

def cleanDirectory(dir)
  puts 'Cleaning directory ' + dir
  FileUtils.rm_rf dir;
  waitfor { !exists?(dir) }
  Dir.mkdir dir
end

def cleanFile(file)
  File.delete file unless !File.exist?(file)
end