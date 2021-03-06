indir=$1
outdir=$2
if [ $# -lt 2 ] ; then
	echo -e "Usage: ./segment.sh <indir> <outdir>
        Looks for a file audio_alignments.txt in <indir> to segment every corresponding .wav file.
        Writes the segmented WAV files, viseme CSV and transcript TXT file to <outdir>" \
    && exit -1;
fi

mkdir -p $outdir

OLDIFS=$IFS
IFS=$'\n'

function write_blendshapes() {
    local audio_file=$1
    local start=$2
    local duration=$3
    local outfile=$4
    echo "Writing BS from start $start dura $duration"
     # make sure we use the calibrated blendshapes if available
    blendshapes=$(find $(dirname $audio_file) -name "*_cal.csv" | head -n1)

    if [ -z "$blendshapes" ]; then
        blendshapes=$(find $(dirname $audio_file) -name "*.csv" | head -n1);
    fi

    head -n1 "$blendshapes" > $outfile
    tail -n+2 $blendshapes | awk -F'[:,]' -v start=$start -v duration=$duration -F':' '{
        hour=$1; min=$2;
        second=($3+($4/59.97));
        time=(hour*60*60)+((min*60)+second);

        if(FNR==1) { 
            offset=time 
        }; 
        normalized=(time-offset); 
        if (normalized > start && normalized < (start+duration)) { 
            print ; 
        }
    }' >> $outfile
    wc -l $outfile
#    if [ $(wc -l $outfile | cut -d' ' -f1) -lt 2 ]; then
#        echo "Error handling blendshapes from $blendshapes";
#    fi
}


# extracts a segment of audio from a WAV file according to the provided start/stop time
# writes the audio to a file ORIGINAL_FILENAME_1.wav 
# writes the transcript to a file ORIGINAL_FILENAME_1.txt
# (where 1/2/3/etc is the segment index)
function segment_audio_at() {
    # the phrase start/stop time and transcript
    local line=$1
    local start=$(echo $line | cut -f1); 
    local duration=$(echo $line | cut -f2); 
    local transcript=$(echo $line | cut -f3);
    local len=$(echo "$transcript" | wc -m)
    if [ $len -lt 2 ]; then
        echo "Error processing $alignment_file";
        exit -1;
    fi

    # the path to the audio_alignments file being used, just for logging
    local alignment_file=$2
    # the source audio file
    local audio_file=$3

    # the number/index of the segment    
    local seg_num=$4;

    if [ -z "$start" ] || [ -z "$duration" ]; then
        echo "Couldn't find start or duration for $alignment_file" && exit;
    fi

    echo "Processing segment $i for file $audio_file";
    local audio_id=$(basename $audio_file | sed "s/\.wav//g")
    echo "$transcript" > $outdir/"${audio_id}_$i".txt
    ffmpeg -n -i $audio_file -ss $start -t $duration -ar 16000 "$outdir/${audio_id}_$i.wav" 2>/dev/null 

    write_blendshapes $audio_file $start $duration "$outdir/${audio_id}_$seg_num.csv"

}

# look for audio_alignments.txt in <indir>
# this contains the start/stop times and accompanying transcript for an audio recording
for alignment_file in $(find $(realpath $indir) -name "audio_alignments.txt"); do
    # find the corresponding audio file
    # there should only be one of these, more than one indicates an error
    audio_file=$(find $(dirname $alignment_file) -name "*.wav" -not -name "*.*.wav" -not -name "*_m2.wav") # _m2 indicates mic2, just skip for now
    if [ $(echo "$audio_file" | wc -l) -ne 1 ]; then
        echo "Multiple audio files found for alignment $alignment_file" && exit -1;
    elif [ -z "$audio_file" ]; then
    	echo "No audio file matching $alignment_file" && exit -1;
    fi
    
    # extract the audio alignments from the file
    audio_alignments=$(cat $alignment_file | awk --field-separator=$'\t' '{printf "%s\t%f\t%s\n",$1,($2-$1),$3}' | sed -E "/^[[:space:]]$/d");
 
    i=0
    # each alignment line corresponds to a single phrase
    # segment the WAV file and write the transcript
    for line in $audio_alignments; do
        if [ -z "$line" ]; then
            continue;
        fi 
        segment_audio_at "$line" $alignment_file $audio_file $i &
        i=$((i+1))
        if [ `expr $i % 5` -eq 0 ]; then
            wait
        fi
    done
    wait
done
IFS=$OLDIFS

