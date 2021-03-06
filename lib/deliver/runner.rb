module Deliver
  class Runner
    attr_accessor :options

    def initialize(options)
      self.options = options
      login
      Deliver::DetectValues.new.run!(self.options)
      FastlaneCore::PrintTable.print_values(config: options, hide_keys: [:app], title: "deliver #{Deliver::VERSION} Summary")
    end

    def login
      Helper.log.info "Login to iTunes Connect (#{options[:username]})"
      Spaceship::Tunes.login(options[:username])
      Spaceship::Tunes.select_team
      Helper.log.info "Login successful"
    end

    def run
      verify_version if options[:app_version].to_s.length > 0
      upload_metadata

      has_binary = options[:ipa] || options[:pkg]
      if !options[:skip_binary_upload] && has_binary
        upload_binary
      end

      Helper.log.info "Finished the upload to iTunes Connect".green

      submit_for_review if options[:submit_for_review]
    end

    # Make sure the version on iTunes Connect matches the one in the ipa
    # If not, the new version will automatically be created
    def verify_version
      app_version = options[:app_version]
      Helper.log.info "Making sure the latest version on iTunes Connect matches '#{app_version}' from the ipa file..."

      changed = options[:app].ensure_version!(app_version)
      if changed
        Helper.log.info "Successfully set the version to '#{app_version}'".green
      else
        Helper.log.info "'#{app_version}' is the latest version on iTunes Connect".green
      end
    end

    # Upload all metadata, screenshots, pricing information, etc. to iTunes Connect
    def upload_metadata
      # First, collect all the things for the HTML Report
      screenshots = UploadScreenshots.new.collect_screenshots(options)
      UploadMetadata.new.load_from_filesystem(options)

      # Validate
      validate_html(screenshots)

      # Commit
      UploadMetadata.new.upload(options)
      UploadScreenshots.new.upload(options, screenshots)
      UploadPriceTier.new.upload(options)
      UploadAssets.new.upload(options) # e.g. app icon
    end

    # Upload the binary to iTunes Connect
    def upload_binary
      Helper.log.info "Uploading binary to iTunes Connect"
      if options[:ipa]
        package_path = FastlaneCore::IpaUploadPackageBuilder.new.generate(
          app_id: options[:app].apple_id,
          ipa_path: options[:ipa],
          package_path: "/tmp"
        )
      elsif options[:pkg]
        package_path = FastlaneCore::PkgUploadPackageBuilder.new.generate(
          app_id: options[:app].apple_id,
          pkg_path: options[:pkg],
          package_path: "/tmp"
        )
      end

      transporter = FastlaneCore::ItunesTransporter.new(options[:username])
      transporter.upload(options[:app].apple_id, package_path)
    end

    def submit_for_review
      SubmitForReview.new.submit!(options)
    end

    private

    def validate_html(screenshots)
      return if options[:force]
      HtmlGenerator.new.run(options, screenshots)
    end
  end
end
