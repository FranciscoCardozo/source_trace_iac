# ------------------------------------------------------------------
# Roles de deploy via OIDC para los repos de las Lambdas.
#
# Un rol por repo/funcion (least-privilege): el workflow de cada repo hace
# `aws lambda update-function-code` sobre SU funcion y nada mas. Reusa el
# mismo OIDC provider de GitHub (token.actions.githubusercontent.com).
#
# Cada entrada de var.lambda_deploy_targets:
#   github_repo     - nombre del repo en GitHub
#   github_repo_id  - ID numerico del repo (subject claim personalizado)
#   function_arn    - ARN de la Lambda que ese repo despliega
# ------------------------------------------------------------------

locals {
  lambda_deploy_roles = {
    for key, t in var.lambda_deploy_targets : key => {
      role_name = "${var.name}_${key}_lambda_deploy_role"
      sub_pattern = (var.github_owner_id != "" && t.github_repo_id != "") ? (
        "repo:${var.github_org}@${var.github_owner_id}/${t.github_repo}@${t.github_repo_id}:${var.deploy_subject_filter}"
      ) : "repo:${var.github_org}/${t.github_repo}:${var.deploy_subject_filter}"
      function_arn = t.function_arn
    }
  }
}

resource "aws_iam_role" "lambda_deploy" {
  for_each = local.lambda_deploy_roles

  name = each.value.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      # configure-aws-credentials pasa session tags -> hace falta sts:TagSession
      # ademas de AssumeRoleWithWebIdentity.
      Action = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = each.value.sub_pattern
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "lambda_deploy" {
  for_each = local.lambda_deploy_roles

  name = "${each.value.role_name}_policy"
  role = aws_iam_role.lambda_deploy[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "UpdateFunctionCode"
      Effect = "Allow"
      Action = [
        "lambda:GetFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:PublishVersion"
      ]
      Resource = each.value.function_arn
    }]
  })
}
