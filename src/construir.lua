#!@@BINDIR@@/fiddle

lfs = {
  root = os.getenv("CONSTRUIR_AQUI") or "."
}

local wat = function(msg)
  print('\27[1;37m== ' .. msg .. '\27[0m')
end

local nak = function(msg)
  print('\27[0;31m--\27[0m ' .. msg)
end

local ack = function(msg)
  print('\27[0;32m++\27[0m ' .. msg)
end

local semver = function(self)
  local v = self.version:gmatch("[^.%s]+")
  return v(), v(), v()
end

local parse = function(target)
  local fenv = { pkg = {} }
  setmetatable(fenv, { __index = _G })
  _ENV = fenv

  setmetatable(pkg, {
    __index = function(self, key)
      local meta = {
        major = function(self) return ({semver(self)})[1] end,
        minor = function(self) return ({semver(self)})[2] end,
        patch = function(self) return ({semver(self)})[3] end
      }

      if type(meta[key]) == "function" then return meta[key](self) end
    end
  })
  _ENV = _G

  local recipe = loadfile(string.format("%s/%s/%s.lua", lfs.root, lfs.recipes, target), "t", fenv)
  if not recipe then
    nak(string.format("parsing recipe (%s) failed", target))
    return nil
  end
  recipe()
  ack(string.format("parsing recipe (%s/%s)", target, fenv.pkg.version))

  return fenv.pkg
end

dofile(string.format("%s/conf/construir.lua", lfs.root))
lfs.recipes = lfs.recipes or "recipes"

wat("construir: a custom linux distribution of your needs")
local target = arg[2]
local pkg = parse(target)
