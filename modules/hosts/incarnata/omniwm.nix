{
  # This desk's monitor arrangement: the MSI ultrawide above the built-in
  # display. OmniWM persists this as routing state keyed by display UUID;
  # declaring the same state here means a switch writes back what the app
  # already believes and the arrangement survives activation.
  flake.modules.darwin."hosts/incarnata" = {
    home-manager.users.k-nanchi = {
      omniwm.extraSettings = {
        routing.mode = "custom";

        monitorRoutingOverrides = [
          {
            gridColumn = 0;
            gridRow = 0;
            monitorDisplayUUID = "FC474059-D931-43CA-A08D-0982ACCBE9E7";
            monitorName = "MSI MD342CQP";
          }
          {
            gridColumn = 0;
            gridRow = 1;
            monitorDisplayUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230";
            monitorName = "Built-in Retina Display";
          }
        ];
      };
    };
  };
}
