Pod::Spec.new do |s|
  s.name             = 'python_bridge'
  s.version          = '1.0.0'
  s.summary          = 'CPython bridge for Flutter'
  s.description      = 'Embedded CPython interpreter bridge'
  s.homepage         = 'https://github.com/naipingzai/flutter_download_manager'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'npznnz' => 'npznnz@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
end
