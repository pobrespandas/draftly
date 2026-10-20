import SwiftUI
import AppKit
import DraftlyCore

func flagColor(_ flag: Int) -> Color {
    switch flag { case 2: .orange; case 3: .yellow; case 4: .green; case 5: .blue; case 6: .purple; case 7: .gray; default: .red }
}
func flagName(_ flag: Int) -> String {
    switch flag { case 2: "Orange"; case 3: "Yellow"; case 4: "Green"; case 5: "Blue"; case 6: "Purple"; case 7: "Gray"; default: "Red" }
}
