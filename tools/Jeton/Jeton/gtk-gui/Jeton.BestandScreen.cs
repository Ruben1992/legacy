// ------------------------------------------------------------------------------
//  <autogenerated>
//      This code was generated by a tool.
//      
// 
//      Changes to this file may cause incorrect behavior and will be lost if 
//      the code is regenerated.
//  </autogenerated>
// ------------------------------------------------------------------------------

namespace Jeton {
    
    
    public partial class BestandScreen {
        
        private Gtk.Label label1;
        
        protected virtual void Build() {
            Stetic.Gui.Initialize(this);
            // Widget Jeton.BestandScreen
            Stetic.BinContainer.Attach(this);
            this.Name = "Jeton.BestandScreen";
            // Container child Jeton.BestandScreen.Gtk.Container+ContainerChild
            this.label1 = new Gtk.Label();
            this.label1.Name = "label1";
            this.label1.LabelProp = Mono.Unix.Catalog.GetString("Bestand edieren und Fehler melden..");
            this.Add(this.label1);
            if ((this.Child != null)) {
                this.Child.ShowAll();
            }
            this.Show();
        }
    }
}
