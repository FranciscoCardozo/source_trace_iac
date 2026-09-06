output "instance_id" {
  description = "ID de la EC2 auxiliar (vacio si enabled = false)"
  value       = var.enabled ? aws_instance.this[0].id : ""
}

output "ssm_command" {
  description = "Comando para entrar por Session Manager"
  value       = var.enabled ? "aws ssm start-session --target ${aws_instance.this[0].id} --region us-east-1" : ""
}

output "download_hint" {
  description = "Comando de descarga a correr dentro de la instancia (reemplazar HF_TOKEN y el archivo)"
  value = var.enabled ? join(" ", [
    "HF_HUB_ENABLE_HF_TRANSFER=1 HF_TOKEN=xxx",
    "hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-IQ2_S.gguf",
    "--local-dir /mnt/model"
  ]) : ""
}
