# Closed-process render traces include each actual render frame, not just packets.
$trace=Get-Content (Join-Path $evidenceRoot 'client-drop-trace.json') -Raw | ConvertFrom-Json
$maxLag=0.0;$maxSmallFrameStep=0.0;$movingFrames=0;$snaps=0;$previous=@{}
foreach($frame in $trace){
 foreach($property in $frame.positions.PSObject.Properties){
  $id=$property.Name;$state=$property.Value
  $lag=Distance $state.visual $state.target
  $maxLag=[Math]::Max($maxLag,$lag)
  if($previous.ContainsKey($id)){
   $targetStep=Distance $state.target $previous[$id].target
   $visualStep=Distance $state.visual $previous[$id].visual
   if($targetStep -gt 0.75){$snaps++;Assert ($lag -lt 0.001) 'Large received correction snaps in the render frame'}
   elseif($visualStep -gt 0.000001){$movingFrames++;$maxSmallFrameStep=[Math]::Max($maxSmallFrameStep,$visualStep)}
  }
  $previous[$id]=$state
 }
}
Assert ($movingFrames -gt 8 -and $maxLag -lt 0.08 -and $maxSmallFrameStep -lt 0.04) 'Measured client drop frames smooth small HOST corrections'
Assert ($snaps -ge 1) 'Measured large correction snap exercised'
foreach($state in $gate.drop_convergence_checkpoint.drop_presentations.PSObject.Properties.Value){
 Assert ((Distance $state.visual $state.target) -lt 0.001) 'Stopped HOST target converges and stops within one millimetre'
}
$gate.drop_metrics=@{render_samples=@($trace).Count;moving_frames=$movingFrames;maximum_target_lag_m=$maxLag;maximum_small_frame_step_m=$maxSmallFrameStep;large_correction_snaps=$snaps;snap_threshold_m=0.75;publication_hz=10;convergence_error_bound_m=0.001;merge_ghosts=0}
$gate.drop_metrics | ConvertTo-Json | Set-Content (Join-Path $evidenceRoot 'drop-metrics.json')
