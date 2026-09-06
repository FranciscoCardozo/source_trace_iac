# ------------------------------------------------------------------
# Roles de deploy via OIDC para repos de frontend (S3 + CloudFront).
#
# Un rol por repo: el workflow hace `aws s3 sync --delete` al bucket y
# `aws cloudfront create-invalidation` en su distribucion, y nada mas.
# Reusa el mismo OIDC provider de GitHub.
# ------------------------------------------------------------------

locals {
  frontend_deploy_roles = {
    for key, t in var.frontend_deploy_targets : key => {
      role_name = "${var.name}_${key}_frontend_deploy_role"
      sub_pattern = (var.github_owner_id != "" && t.github_repo_id != "") ? (
        "repo:${var.github_org}@${var.github_owner_id}/${t.github_repo}@${t.github_repo_id}:${var.deploy_subject_filter}"
      ) : "repo:${var.github_org}/${t.github_repo}:${var.deploy_subject_filter}"
      bucket_arn                  = t.bucket_arn
      cloudfront_distribution_arn = t.cloudfront_distribution_arn
    }
  }
}

resource "aws_iam_role" "frontend_deploy" {
  for_each = local.frontend_deploy_roles

  name = each.value.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
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

resource "aws_iam_role_policy" "frontend_deploy" {
  for_each = local.frontend_deploy_roles

  name = "${each.value.role_name}_policy"
  role = aws_iam_role.frontend_deploy[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = each.value.bucket_arn
      },
      {
        Sid      = "SyncObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${each.value.bucket_arn}/*"
      },
      {
        Sid      = "InvalidateCache"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = each.value.cloudfront_distribution_arn
      }
    ]
  })
}
