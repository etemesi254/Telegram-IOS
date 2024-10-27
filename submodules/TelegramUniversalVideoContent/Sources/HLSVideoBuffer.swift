import FFMpegBinding
import Foundation


public struct RingBuffer : ~Copyable{
    fileprivate var array: Array<HlsOutputData> = Array();
    // make it thread safe
    public var readIndex = 0
    public var writeIndex = 0
    public var lookahead = 0
    
    public mutating func clear(){
        self.readIndex=0
        self.writeIndex=0
        self.lookahead=0
    }
    
    
    public init(count: Int) {
        array = Array();
        array.reserveCapacity(count);
        // initialize separate ones
        for _ in 0...count-1{
            array.append(HlsOutputData());
        }
    }
    public mutating func increaseByOne(){
        array.append(HlsOutputData())
    }
    
    // it may be very non-threaded
    // TODO: (cae), check if thread reordering affects stuff
    // probably does.
    public mutating func writeVideo(_ element: HlsOutputData,position:Int) -> Bool {
        if !isFull {
            element.cloneVideo(array[position % array.count]);
            assert(element.videoSize == array[position % array.count].videoSize);
            writeIndex += 1
            return true
        } else {
            return false
        }
    }
    public mutating func writeAudio(_ element: HlsOutputData,position:Int) -> Bool {
        if !isFull {
            element.cloneAudio(array[position % array.count]);
            assert(element.audioData?.length == array[position % array.count].audioData?.length);
            writeIndex += 1
            return true
        } else {
            return false
        }
    }
    public mutating func read() -> HlsOutputData? {
        if !isEmpty {
            let element = array[readIndex % array.count]
            return element
        } else {
            return nil
        }
    }
    public mutating func acknowledgeRead(){
        self.readIndex+=1;
    }
    
    fileprivate var availableSpaceForReading: Int {
        return writeIndex - readIndex
    }
    
    public var isEmpty: Bool {
        return availableSpaceForReading == 0
    }
    
    fileprivate var availableSpaceForWriting: Int {
        return array.count - availableSpaceForReading
    }
    
    public var isFull: Bool {
        return availableSpaceForWriting == 0
    }
    public func dealloc(){
        for i in 0...self.array.count-1{
            if (self.array[i].videoData != nil){
                free(self.array[i].videoData);
                self.array[i].videoSize=0;
            }
        }
    }
    deinit {
        dealloc()
    }
}
