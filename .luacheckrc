read_globals = {
  vim = {
    other_fields = true,
    fields = {
      g = {
        read_only = false,
        other_fields = true
      }
    }
  }
}
include_files = {'lua/', '*.lua'}
exclude_files = {'lua/scrollview/signs/contrib/README'}
std = 'luajit'
