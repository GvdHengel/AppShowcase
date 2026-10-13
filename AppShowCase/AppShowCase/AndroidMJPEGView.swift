import SwiftUI

struct AndroidMJPEGView: View {
    @ObservedObject var service: MJPEGScreencapService
    
    var body: some View {
        ZStack {
            Color.black
            if let frame = service.currentFrame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView("Verbinden met MJPEG Stream...")
                    .foregroundColor(.white)
            }
            
            VStack {
                HStack {
                    Spacer()
                    Text("\(String(format: "%.1f", service.fps)) fps")
                        .font(.caption2)
                        .padding(4)
                        .background(.black.opacity(0.5))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                        .padding(8)
                }
                Spacer()
            }
        }
    }
}
