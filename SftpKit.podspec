Pod::Spec.new do |spec|
  spec.name             = 'SftpKit'
  spec.version          = '0.0.1'
  spec.summary          = 'A tiny Swift SSH framework that wraps libssh2.'
  spec.homepage         = 'https://github.com/bugix/SftpKit'
  spec.license          = 'MIT'
  spec.authors          = { 'Martin Imobersteg' => 'martin.imobersteg@gmail.com' }
  spec.source           = { :git => 'https://github.com/bugix/SftpKit.git', :tag => spec.version.to_s }

  spec.requires_arc     = true
  spec.default_subspec  = 'Libssh2'
  spec.swift_version    = '5.0'

  spec.ios.deployment_target = '12.0'

  spec.subspec 'Core' do |core|
      core.source_files = 'SftpKit/*.swift'
      core.exclude_files = 'SftpKit/Libssh2*'
  end

  spec.subspec 'Libssh2' do |libssh2|
      libssh2.dependency 'SftpKit/Core'
      libssh2.libraries = 'z'
      libssh2.preserve_paths = 'libssh2'
      libssh2.source_files = 'SftpKit/Libssh2*.{h,m,swift}'
      libssh2.pod_target_xcconfig = {
        'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
        'SWIFT_INCLUDE_PATHS' => '$(PODS_ROOT)/SftpKit/libssh2',
        'LIBRARY_SEARCH_PATHS' => '$(PODS_ROOT)/SftpKit/libssh2',
        'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/SftpKit/libssh2'
      }
  end

end
