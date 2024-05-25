local Job = require("plenary.job")
local log = require("plenary.log").new({ plugin = "jenkinsfile-linter", level = "info" })

local jenkins_password = os.getenv("JENKINS_PASSWORD")
local jenkins_token = os.getenv("JENKINS_API_TOKEN") or os.getenv("JENKINS_TOKEN")
local jenkins_url = os.getenv("JENKINS_URL") or os.getenv("JENKINS_HOST")
local jenkins_user = os.getenv("JENKINS_USER_ID") or os.getenv("JENKINS_USERNAME")
local jenkins_validation_url = jenkins_url .. "/pipeline-model-converter/validate"
local namespace_id = vim.api.nvim_create_namespace("jenkinsfile-linter")
local validated_msg = "Jenkinsfile successfully validated."


local function validate_job()
  -- Buffers to collect the output and errors
  local result = {}
  local errors = {}

  -- Execute the curl command asynchronously using plenary.job
  Job:new({
    command = "curl",
    args = {
      "--silent",
      "--user",
      string.format("%s:%s", jenkins_user, jenkins_token or jenkins_password),
      "-X",
      "POST",
      jenkins_validation_url,
      "-F",
      string.format("jenkinsfile=<%s", vim.fn.expand("%:p")),
    },
    on_stdout = function(_, line)
      table.insert(result, line)
    end,
    on_stderr = function(_, line)
      table.insert(errors, line)
    end,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val == 0 then
          -- Join all lines to form the full result string
          local full_result = table.concat(result, "\n")

          -- Remove leading and trailing whitespace
          full_result = full_result:gsub("^%s+", ""):gsub("%s+$", "")

          -- Validate result
          if full_result == validated_msg then
            vim.notify(full_result, vim.log.levels.INFO)
          else
            local msg, line_str, col_str = full_result:match("WorkflowScript.+%d+: (.+) @ line (%d+), column (%d+).")
            if line_str and col_str then
              local line = tonumber(line_str) - 1
              local col = tonumber(col_str) - 1

              local diag = {
                bufnr = vim.api.nvim_get_current_buf(),
                lnum = line,
                end_lnum = line,
                col = col,
                end_col = col,
                severity = vim.diagnostic.severity.ERROR,
                message = msg,
                source = "jenkinsfile validation",
              }

              vim.diagnostic.set(namespace_id, vim.api.nvim_get_current_buf(), { diag })
              vim.notify(full_result, vim.log.levels.ERROR)
            else
              -- Get the last line
              local last_line = ""
              for line in full_result:gmatch("[^\r\n]+") do
                  last_line = line
              end

              vim.notify(validated_msg .. "\n\n" .. last_line, vim.log.levels.WARN)
              local full_error = table.concat(errors, "\n")
              vim.notify(full_error, vim.log.levels.ERROR)
            end
          end
        else
          -- Join and notify error messages
          local full_error = table.concat(errors, "\n")
          vim.notify("Failed to validate Jenkinsfile:\n\n" .. full_error, vim.log.levels.ERROR)
          log.error(full_error)
        end
      end)
    end,
  }):start()
end

local function check_creds()
  if jenkins_user == nil then
    return false, "JENKINS_USER_ID is not set, please set it"
  elseif jenkins_password == nil and jenkins_token == nil then
    return false, "JENKINS_PASSWORD or JENKINS_API_TOKEN need to be set."
  elseif jenkins_url == nil then
    return false, "JENKINS_URL is not set."
  else
    return true
  end
end

local function validate()
  local ok, msg = check_creds()
  if ok then
    validate_job()
  else
    vim.notify(msg, vim.log.levels.ERROR)
    log.error(msg)
  end
end

return {
  validate = validate,
  check_creds = check_creds,
}
