require 'pty'
require 'open3'

module Gym
  class Runner
    # @return (String) The path to the resulting ipa
    def run
      clear_old_files
      build_app
      verify_archive
      package_app
      Gym::XcodebuildFixes.swift_library_fix
      Gym::XcodebuildFixes.watchkit_fix
      move_results
    end

    #####################################################
    # @!group Printing out things
    #####################################################

    # @param [Array] An array containing all the parts of the command
    def print_command(command, title)
      rows = command.map do |c|
        current = c.to_s.dup
        next unless current.length > 0

        if current.include? "-" and current.to_s.split(" '").count == 2
          # That's a default parameter, like `-project 'Name'`
          # We use " '" to not split by spaces within the value (e.g. path)
          current.split(" '")
        else
          current.gsub!("| ", "") # as the | will somehow break the terminal table
          [current, ""]
        end
      end

      puts Terminal::Table.new(
        title: title.green,
        headings: ["Option", "Value"],
        rows: rows.delete_if { |c| c.to_s.empty? }
      )
    end

    private

    #####################################################
    # @!group The individual steps
    #####################################################

    def clear_old_files
      if File.exist? PackageCommandGenerator.ipa_path
        File.delete(PackageCommandGenerator.ipa_path)
      end
    end

    # Builds the app and prepares the archive
    def build_app
      command = BuildCommandGenerator.generate
      print_command(command, "Generated Build Command") if $verbose
      FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: !Gym.config[:silent],
                                              error: proc do |output|
                                                ErrorHandler.handle_build_error(output)
                                              end)

      Helper.log.info("Successfully stored the archive. You can find it in the Xcode Organizer.".green)
      Helper.log.info("Stored the archive in: ".green + BuildCommandGenerator.archive_path) if $verbose
    end

    # Makes sure the archive is there and valid
    def verify_archive
      if Dir[BuildCommandGenerator.archive_path + "/*"].count == 0
        ErrorHandler.handle_empty_archive
      end
    end

    def package_app
      command = PackageCommandGenerator.generate
      print_command(command, "Generated Package Command") if $verbose

      FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: !Gym.config[:silent],
                                              error: proc do |output|
                                                ErrorHandler.handle_package_error(output)
                                              end)
    end

    # Moves over the binary and dsym file to the output directory
    # @return (String) The path to the resulting ipa file
    def move_results
      require 'fileutils'

      FileUtils.mv(PackageCommandGenerator.ipa_path, Gym.config[:output_directory], force: true)

      if PackageCommandGenerator.dsym_path
        # Compress and move the dsym file
        containing_directory = File.expand_path("..", PackageCommandGenerator.dsym_path)
        file_name = File.basename(PackageCommandGenerator.dsym_path)

        output_path = File.expand_path(File.join(Gym.config[:output_directory], Gym.config[:output_name] + ".app.dSYM.zip"))
        command = "cd '#{containing_directory}' && zip -r '#{output_path}' '#{file_name}'"
        Helper.log.info command.yellow unless Gym.config[:silent]
        command_result = `#{command}`
        Helper.log.info command_result if $verbose

        puts "" # new line

        Helper.log.info "Successfully exported and compressed dSYM file.".green
      end

      ipa_path = File.join(Gym.config[:output_directory], File.basename(PackageCommandGenerator.ipa_path))

      Helper.log.info "Successfully exported and signed ipa file:".green
      Helper.log.info ipa_path
      ipa_path
    end
  end
end
