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
exclude_files = {'lua/scrollview/contrib/README'}
std = 'luajit'
