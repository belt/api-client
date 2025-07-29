variable "API_CLIENT_VERSION" {
  default = "1.0"
}

variable "TS" {
  default = "unknown"
}

variable "CACHE_BUMP_APT" { default = "" }
variable "CACHE_BUMP_GEMS" { default = "" }

function "build_args_for" {
  params = [ruby, jit, target]
  result = {
    RUBY_VERSION = ruby
    RUBY_YJIT_ENABLE = jit == "yjit" ? "1" : ""
    RUBY_ZJIT_ENABLE = jit == "zjit" ? "1" : ""
    BUILD_DATE = TS
    CACHE_BUMP_APT = CACHE_BUMP_APT
    CACHE_BUMP_GEMS = CACHE_BUMP_GEMS
    INSTALL_MANPAGES = target == "development" ? "1" : ""
    INSTALL_LESS = target == "development" ? "1" : ""
    INSTALL_VIM = target == "development" ? "1" : ""
    INSTALL_MISE = target == "development" ? "1" : ""
  }
}

function "ruby_minor" {
  params = [r]
  result = join(".", [split(".", r)[0], split(".", r)[1]])
}

target "matrix" {
  name = "${targ}-${replace(item.ruby, ".", "-")}-${item.jit}"
  matrix = {
    item = [
      { ruby = "3.3.10", jit = "yjit" },
      { ruby = "3.4.8", jit = "yjit" },
      { ruby = "4.0.1", jit = "yjit" },
      { ruby = "4.0.1", jit = "zjit" }
    ]
    targ = ["production", "development"]
  }

  target = targ
  args = build_args_for(item.ruby, item.jit, targ)
  tags = ["ruby-${item.jit}-${ruby_minor(item.ruby)}-api-client-${API_CLIENT_VERSION}-${targ == "production" ? "prod" : "develop"}"]

  cache-from = ["type=local,src=tmp/buildkit-cache"]
  cache-to   = ["type=local,dest=tmp/buildkit-cache-new,mode=max"]
}

group "default" {
  targets = ["matrix"]
}
