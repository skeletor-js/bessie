import BessieCore
import SwiftUI

struct RuntimeSettingsView: View {
    @EnvironmentObject private var model: BessieSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BessieSectionLabel("HERDR RUNTIME")
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Included compatible runtime")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BessieDesign.strong)
                    Text("Bessie V1 always uses its signed, bundled Herdr runtime. There is nothing to choose or install.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(BessieDesign.subtle)
                }
                Spacer(minLength: 20)
                Text("Included")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BessieDesign.strong)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
            if let error = model.runtimePersistenceError {
                Text(error).font(.system(size: 11)).foregroundStyle(BessieDesign.destructive)
            }
        }
    }
}
