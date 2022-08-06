#include <iostream>
#include <iomanip>
#include <fstream>
#include <sstream>
#include <string>
#include <list>
#include <set>
#include <vector>
#include <ctype.h>

#include "mamegame.hpp"


using namespace std;

struct Frac {
    int step; // number of bytes to take at once
    int count; // number of fractions
};


set<string> swapregions;
set<string> fillregions;
set<string> ignoreregions;
map<string,int> startregions;
map<string,Frac> fracregions;

class DIP_shift {
public:
    string name;
    int shift;
};

typedef list<DIP_shift> shift_list;

class Header {
    int *buf;
    int _size, _offsetbits;
    int pos, offset_lut;
    bool reverse;
    vector<string> regions;
public:
    Header(int size, int fill);
    ~Header();
    int get_size() { return _size; }
    int* data() { return buf; }
    void push( int v );
    bool set_pointer( int p );
    // Offset list
    bool set_offset_lut( int start ) { offset_lut = start; return start<_size && start>=0; }
    void set_offsetbits( int offsetbits ) { _offsetbits = offsetbits; }
    void add_region(const char *s) { regions.push_back(s); }
    bool set_offset( const string& s, int offset );
    void set_reverse() { reverse = true; }
};

void clean_filename( string& fname );
void rename_regions( Game *g, list<string>& renames );

struct ROMorder {
    string region;
    string order;
};

class MRAmaker {
    void makeROM( class Node& root, Game* g );
    int parse_rom_offset( Node& root, ROMRegion* region );
    void makeNVRAM( class Node& root );
public:
    int nvram_idx, nvram_size;
    string buttons, altfolder, outdir, dipbase, rbf;
    int mod_or;
    bool qsound;
    class Header *header;
    shift_list shifts;
    MRAmaker() : qsound(false), header(NULL), outdir("."), mod_or(0), dipbase("16"),
        nvram_idx(-1), nvram_size(0) { }
    ~MRAmaker() {
        if(header) {
            delete header;
            header = NULL;
        }
    }
    void makeMRA( Game* g );
};

struct ConfigRegion {
    int word_length;
    bool reverse;
};

int main(int argc, char * argv[] ) {
    bool print=false;
    string fname="mame.xml";
    bool   fname_assigned=false;
    string region_order;
    string machine;
    list<string> rmdipsw, renames;
    list<ROMorder> rom_order;
    map<string,ConfigRegion> region_widths;
    MRAmaker maker;
try{
    for( int k=1; k<argc; k++ ) {
        string a = argv[k];
        if( a=="-swapbytes" ) {
            while( ++k < argc && argv[k][0]!='-' ) {
                swapregions.insert(argv[k]);
            }
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        if( a=="-machine" ) {
            k++;
            if( k>=argc ) {
                cout << "ERROR: expecting machine name after -machine\n";
                return 1;
            }
            machine = argv[k];
            continue;
        }
        if( a=="-fill" ) {
            fillregions.insert(string(argv[++k]));
            continue;
        }
        if( a=="-start" ) {
            string reg(argv[++k]);
            int offset=strtol( argv[++k], NULL, 0 );
            startregions[reg]=offset;
            continue;
        }
        if( a=="-dipbase" ) {
            maker.dipbase=argv[++k];
            continue;
        }
        if( a=="-dipshift" ) {
            assert(argc>k+2);
            maker.shifts.push_back( {argv[++k], (int)strtol(argv[++k], NULL,0) });
            continue;
        }
        if( a=="-ignore" ) {
            while( ++k<argc && argv[k][0]!='-' )
                ignoreregions.insert(string(argv[k]));
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        if( a=="-setword" ) {
            if( k+2>=argc ) {
                cout << "ERROR: incomplete setword argument\n";
                return 1;
            }
            string reg_name = argv[++k];
            int reg_width = atol(argv[++k]);
            if( reg_width!=16 && reg_width!=32 && reg_width!=64 ) {
                cout << "ERROR: setword can only be used to set widths of 16, 32 and 64 bits\n";
                return 1;
            }
            ConfigRegion cfg = { reg_width, false };
            if( k+1 < argc ) {
                if( argv[k+1][0] != '-' ) {
                    ++k;
                    if( strcmp(argv[k],"reverse") ==0 )
                        cfg.reverse = true;
                    else {
                        cout << "ERROR: unexpected '" << argv[k] << "' after -setword command\n";
                        return 1;
                    }
                }
            }
            region_widths[reg_name]=cfg;
            continue;
        }
        if( a=="-frac" ) {
            Frac frac = {1,1};
            if( k+2>=argc ) {
                cout << "ERROR: incomplete frac argument\n";
                return 1;
            }
            string reg(argv[++k]);
            if( argv[k][0]>='0' && argv[k][0]<='9' ) {
                frac.step = strtol(argv[k],NULL,0);
                if(frac.step<1 || frac.step>2) {
                    cout << "ERROR: frac step can only be 1 or 2\n";
                    return 1;
                }
                reg = argv[++k];
                if( k>=argc ) {
                    cout << "ERROR: incomplete frac argument\n";
                    return 1;
                }
            }
            frac.count=strtol( argv[++k], NULL, 0 );
            fracregions[reg]=frac;
            continue;
        }
        if( a=="-rbf" ) {
            maker.rbf=argv[++k];
            continue;
        }
        if( a=="-outdir" ) {
            maker.outdir=argv[++k];
            continue;
        }
        if( a=="-altfolder" ) {
            maker.altfolder = argv[++k];
            continue;
        }
        if( a=="-buttons" ) {
            string& buttons=maker.buttons;
            while( ++k < argc && argv[k][0]!='-' ) {
                if(buttons.size()==0)
                    buttons=argv[k];
                else {
                    string b(argv[k]);
                    if( b=="None" || b=="none" ) b="-";
                    buttons+=string(" ") + b;
                }
            }
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        if( a=="-rmdipsw" ) {
            while( ++k < argc && argv[k][0]!='-' ) {
                rmdipsw.push_back(argv[k]);
            }
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        if( a=="-rename" ) {
            while( ++k < argc && argv[k][0]!='-' ) {
                if( strchr( argv[k], '=' )==NULL ) {
                    throw "ERROR: wrong syntax in rename argument\n"
                          "       correct format is newname=oldname\n";
                }
                renames.push_back(argv[k]);
            }
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        // Header support
        if( a=="-header" ) {
            if( maker.header!=NULL ) {
                throw "ERROR: header had already been defined\n";

            }
            int aux=strtol(argv[++k], NULL, 0);
            if( aux<=0 || aux>128 ) {
                throw "ERROR: header must be smaller than 128 bytes\n";
            }
            int fill=0;
            if( argv[k+1][0]!='-' ) {
                fill=strtol(argv[++k], NULL, 0);
                if( fill<=0 || fill>255 ) {
                    throw "ERROR: fill value must be between 0 and 255\n";
                }
            }
            maker.header = new Header(aux, fill);
            continue;
        }
        if( a=="-header-data" ) {
            if( maker.header==NULL) {
                throw "ERROR: header size has not been defined\n";
            }
            while( ++k<argc && argv[k][0]!='-' ) {
                int aux=strtol(argv[k], NULL, 16);
                if( aux<0 || aux>255 ) {
                    throw "ERROR: header data must be written in possitive bytes\n";
                }
                maker.header->push(aux);
            }
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        if( a=="-header-offset-bits" ) {
            if( maker.header==NULL) {
                throw "ERROR: header size has not been defined\n";
            }
            ++k;
            if( k>= argc ) {
                throw "ERROR: missing value for header offset bits\n";
            }
            int aux = strtol( argv[k], NULL, 0);
            if( aux<0 || aux>16 ) {
                throw "ERROR: header offset bits value must between 0 and 16\n";
            }
            maker.header->set_offsetbits(aux);
            continue;
        }
        if( a=="-header-pointer" ) {
            if( maker.header==NULL) {
                throw "ERROR: header size has not been defined\n";
            }
            ++k;
            if( k>= argc ) {
                throw "ERROR: missing value for header pointer\n";
            }
            int aux = strtol( argv[k], NULL, 0);
            if( aux<0 || aux>maker.header->get_size()-1 ) {
                throw "ERROR: header pointer is outside the header area\n";
            }
            maker.header->set_pointer(aux);
            continue;
        }
        if( a=="-header-offset" ) {
            if( maker.header==NULL) {
                throw "ERROR: header size has not been defined\n";
            }
            assert( ++k < argc );
            int aux = strtol( argv[k], NULL, 0);
            if( !maker.header->set_offset_lut( aux ) ) {
                throw "ERROR: header offset LUT is out of bounds\n";
            }
            while( ++k<argc && argv[k][0]!='-') maker.header->add_region(argv[k]);
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        if( a=="-header-offset-reverse" ) {
            if( maker.header==NULL) {
                throw "ERROR: header size has not been defined\n";
            }
            maker.header->set_reverse();
            continue;
        }
        // MOD MRAmaker
        if( a=="-4way" ) {
            maker.mod_or |= 2;
            continue;
        }
        // ROM order
        if( a=="-order" ) {
            while( ++k < argc && argv[k][0]!='-' ) {
                region_order = region_order + argv[k] + string(" ");
            }
            if( k<argc && argv[k][0]=='-' ) k--;
            continue;
        }
        if( a=="-order-roms" ) {
            assert( ++k < argc );
            ROMorder o;
            o.region = argv[k];
            while( ++k < argc && argv[k][0]!='-' ) {
                o.order = o.order + argv[k] + string(" ");
            }
            if( k<argc && argv[k][0]=='-' ) k--;
            rom_order.push_back(o);
            continue;
        }
        if( a=="-qsound" ) {
            maker.qsound=true;
            continue;
        }
        // NVRAM
        if( a=="-nvram" ) {
            assert( ++k < argc );
            maker.nvram_idx = 2; // enable NVRAM
            maker.nvram_size = strtol( argv[k], NULL, 0 );
            if( maker.nvram_size <0 || maker.nvram_size>1024 ) {
                throw "ERROR: Unsupported NVRAM size\n";
            }
            continue;
        }
        // Help
        if( a == "-help" || a =="-h" ) {
            cout << "mame2dip: converts MAME XML dump to MRA format\n"
                    "          by Jose Tejada. Part of JTFRAME\n"
                    "Usage:\n"
                    "          first argument:  path to file containing 'mame -listxml' output\n"
                    "    -rbf       <name>          set RBF file name\n"
                    "    -machine   <name>          process only the given machine\n"
                    "    -buttons   shoot jump etc  Gives names to the input buttons\n"
                    "    -altfolder path            Path where MRA for clone games will be added\n"
                    "    -outdir    path            Base path for output MRA files\n"
                    "\n DIP MRAmaker\n"
                    "    -dipbase   <number>        First bit to use as DIP setting in MiST status word\n"
                    "    -dipshift  <name> <number> Shift bits of DIPSW name by given ammount\n"
                    "    -rmdipsw   <name> ...      Deletes the give DIP switch from the output MRA\n"
                    "\n Region MRAmaker\n"
                    "    -order     regions         define the dump order of regions. Those not enumerated\n"
                    "                               will get dumped last\n"
                    "    -order-roms region # # #   ROMs of specified regions are re-ordered. Index starts\n"
                    "                               with zero. Unspecified ROMs will not be used.\n"
                    "    -ignore    <region>        ignore a given region\n"
                    "    -start     <region>        set start of region in MRA file\n"
                    "    -swapbytes <region>        swap bytes for named region\n"
                    "    -frac      <region> <#>    divide region in fractions\n"
                    "    -fill      <region>        fill gaps between files within region\n"
                    "    -rename    old=new?        rename region old by new. Add ? to skip warning messages\n"
                    "                               if old is not found.\n"
                    "    -setword <region> <bits> [reverse]  "
                    "                               sets the word width in bits of a region.\n"
                    "                               Valid values are 16, 32 and 64 only.\n"
                    "                               The optional reverse keyword will reverse the order\n"
                    "                               of the ROM files inside each interleave section.\n"
                    "\n Header MRAmaker \n"
                    "    -header    size [fill]     Defines an empty (zeroes) header of the given size\n"
                    "                               The optional fill value sets the default value of the header bytes\n"
                    "    -header-data value         Pushes data to the header. It can be defined multiple times\n"
                    "    -header-offset start regions\n"
                    "                               Start is the first byte where the regions offsets will be dumped\n"
                    "                               The bottom 8 bits of the offsets are dropped. Each offset is written\n"
                    "                               as two bytes. \"regions\" is a list of words with the MAME name of\n"
                    "                               the ROM regions\n"
                    "    -header-offset-bits value  Number of bits to cut from offset data. Default is 8.\n"
                    "    -header-offset-reverse     The two bytes for each data offset will be dumped in reverse order\n"
                    "\n Mod byte MRAmaker \n"
                    "    -4way                      Sets 4-way joystick input\n"
                    "\n NVRAM support \n"
                    "    -nvram size                Enables NVRAM support for the given size (up to 1024 bytes)"
                    "\n Common ROMs\n"
                    "    -qsound                    Adds chunk for loading q-sound internal ROM\n"
            ;
            return 0;
        }
        if( !fname_assigned ) {
            fname = argv[k];
            fname_assigned = true;
        } else {
            cout << "Unknown argument " << argv[k] << "\n";
            throw "ERROR\n";
        }
    }
} catch( const char *s ) {
    cout << s;
    return 1;
}
    GameMap games;
    parse_MAME_xml( games, fname.c_str() );
    for( auto& g : games ) {
        Game* game=g.second;
        if( machine.size() ) {
            if( game->name != machine ) continue;
        }
        // Rename ROM regions
        rename_regions( game, renames );
        // Remove unused dip swithces
        ListDIPs& dips=game->getDIPs();
        list<ListDIPs::iterator> todelete;
        if( rmdipsw.size()>0 ) {
            for( ListDIPs::iterator k=dips.begin(); k!=dips.end(); k++ ) {
                DIPsw* sw = *k;
                for( auto s : rmdipsw ) {
                    if( sw->name == s ) {
                        todelete.push_back(k);
                        break;
                    }
                }
            }
        }
        for( auto k : todelete ) {
            delete *k;
            dips.erase(k);
        }
        cout << game->name << '\n';
        // Sort ROMs
        for( auto o : rom_order ) {
            ROMRegion* region = game->getRegion( o.region, false );
            if( region==NULL ) {
                cout << "WARNING: order-roms argument cannot be applied to " << game->name << '\n';
                break;
            }
            region->sort(o.order.c_str());
        }
        // Add width information
        for( auto& wr : region_widths ) {
            ROMRegion* region = game->getRegion( wr.first, false );
            if( region==nullptr ) {
                cout << "Error: cannot find region " << wr.first << " used in -setword argument\n";
                return 1;
            }
            region->word_length = wr.second.word_length;
            region->reverse = wr.second.reverse;
        }
        game->sortRegions(region_order.c_str());
        maker.makeMRA(game);
    }
    return 0;
}

void rename_regions( Game *g, list<string>& renames ) {
    ListRegions& regions = g->getRegionList();
    for( string& s : renames ) {
        size_t strpos = s.find_first_of('=');
        string newname = s.substr(0, strpos);
        string oldname = s.substr(strpos+1);
        bool found=false, nowarning=false;
        if( oldname[oldname.size()-1]=='?' ) {
            nowarning = true;
            oldname = oldname.substr(0, oldname.size()-1);
        }
        for( ROMRegion* reg : regions ) {
            if( reg->name == oldname ) {
                reg->name=newname;
                found=true;
                break;
            }
        }
        if( !found && !nowarning) {
            cout << "Warning: renamed failed for " << g->name << " region '" << oldname << "'. It was not found\n";
        }
    }
}

void replace( string&aux, const char *find_text, const char* new_text ) {
    int pos;
    int n = strlen(find_text);
    while( (pos=aux.find(find_text))!=string::npos ) {
        aux.replace(pos,n,new_text);
    }
}

struct Attr {
    string name, value;
};

class Node {
    list<Node*> nodes;
    list<Attr*> attrs;
    bool is_comment;
public:
    string name, value;
    Node( string n, string v="" );
    Node& add( string n, string v="");
    Node& add_front( string n, string v="");
    void add_attr( string n, string v="");
    void add_attr( string n, int v );
    void dump(ostream& os, string indent="" );
    void comment( string v );
    virtual ~Node();
};

int dump_rom( Node& parent, ROM* r, string map_str="" ) {
    Node& part = parent.add("part");
    part.add_attr("name",r->name);
    part.add_attr("crc",r->crc);
    if( map_str.size()>0 ) {
        part.add_attr("map",map_str);
    }
    return r->size;
}

string make_map_string( int k, int step_bytes, int word_bytes ) {
    char s[]="00000000";
    if( word_bytes<=8 && step_bytes*(k+1)<=8 ) {
        s[word_bytes] = 0;
        int p = word_bytes-(k+1)*step_bytes;
        for( ; step_bytes>0; step_bytes--,p++ ) {
            s[p] = '0' + step_bytes;
        }
    }
    return string(s);
}

int MRAmaker::parse_rom_offset( Node& root, ROMRegion* region ) {
    list <ListROMs*> groups;
    int offset=-1;
    bool groups_exist=false;
    int dumped=0;

    if( region->word_length<16 ) return 0;

    for( ROM* r : region->roms ) {
        int cur_offset = r->offset & ~7;
        // cout << r->name << " " << hex << cur_offset << " (" << hex << offset << ")" << '\n';
        if( cur_offset != offset) {
            ListROMs* newgroup = new ListROMs;
            newgroup->push_back(r);
            groups.push_back(newgroup);
            offset = cur_offset;
        } else {
            groups.back()->push_back(r);
            groups_exist = true; // there is at least one group
        }
    }
    if( groups_exist ) {
        for( ListROMs* g : groups ) {
            const int steps = g->size();
            if( steps==1 ) {
                dumped += dump_rom( root, g->front() );
            } else {
                Node& n = root.add("interleave");
                n.add_attr("output",region->word_length);
                int word_bytes = region->word_length/8;
                int step_bytes = word_bytes/steps;
                bool reverse = region->reverse;
                ListROMs::iterator cur_rom = reverse ? g->end() : g->begin();
                if(reverse ) cur_rom--;
                for( int k=0; k<steps; k++ ) {
                    string map_str = make_map_string(k, step_bytes, word_bytes);
                    dumped += dump_rom( n, *cur_rom, map_str );
                    if(reverse) cur_rom--; else cur_rom++;
                }
            }
        }
    }
    // clear memory
    for( ListROMs* g : groups ) {
        delete g;
    }
    return dumped;
}

void MRAmaker::makeROM( Node& root, Game* g ) {
    Node& n = root.add("rom");
    n.add_attr("index","0");
    string zips = g->name+".zip";
    if( g->cloneof.size() ) {
        zips = zips + "|" + g->cloneof+".zip";
    }
    if( qsound ) zips += "|qsound.zip";
    n.add_attr("zip",zips);
    n.add_attr("type","merged");
    n.add_attr("md5","None"); // important or MiSTer will not let the game boot
    int dumped=0;
    g->moveRegionBack("proms"); // This region should appear last
    for( ROMRegion* region : g->getRegionList() ) {
        if ( ignoreregions.count(region->name)>0 ) continue;
        auto start_offset = startregions.find(region->name);
        if( start_offset != startregions.end() ) {
            int s = start_offset->second;
            int rep = s-dumped;
            if( rep<0 ) {
                cout << "WARNING: required start value is too low for "
                " region " << region->name << '\n';
            } else if( rep>0 ) {
                Node& fill = n.add("part","FF");
                char buf[32];
                snprintf(buf,32,"0x%X",rep);
                fill.add_attr("repeat",buf);
                dumped=s;
            }
        }
        char title[128];
        snprintf(title,128,"%s - starts at 0x%X", region->name.c_str(), dumped );
        if( header ) header->set_offset( region->name, dumped );
        n.comment( title );
        bool swap = swapregions.count(region->name)>0;
        bool fill = fillregions.count(region->name)>0;
        // is it a fractioned region?
        auto frac_idx = fracregions.find(region->name);
        Frac frac={0,0};
        if( frac_idx!= fracregions.end() ) {
            frac = frac_idx->second;
        }
        string frac_output="0";
        switch( frac.count ) {
            case 2: frac_output= frac.step==1 ? "16" : "32"; break;
            case 4: frac_output= frac.step==1 ? "32" : "64"; break;
            case 0: break;
            default: cout << "WARNING: unsupported frac value for region "
                          << region->name << "\n";
                     continue;
        }
        if( frac.count==0 ) {
            int group_dump = parse_rom_offset( n, region );
            if( group_dump==0 ) {
                int offset=0;
                for( ROM* r : region->roms ) {
                    // Fill in gaps between ROM chips
                    if( offset != r->offset && fill) {
                        Node& part = n.add("part","FF");
                        int rep = r->offset - offset;
                        char buf[32];
                        snprintf(buf,32,"0x%X",rep);
                        part.add_attr("repeat",buf);
                        dumped += rep;
                    }
                    Node& parent = swap ? n.add("interleave") : n;
                    if( swap ) {
                        parent.add_attr("output","16");
                    }
                    Node& part = parent.add("part");
                    part.add_attr("name",r->name);
                    part.add_attr("crc",r->crc);
                    if( swap ) {
                        part.add_attr("map","12");
                    }
                    offset = r->offset + r->size;
                    dumped += r->size;
                }
            } else {
                dumped += group_dump;
            }
        } else {
            // Fractioned ROMs
            // First check that the count is correct
            if( region->roms.size()%frac.count != 0 ) {
                cout << "WARNING: Total number of ROM entries does not much fraction value"
                    " for region " << region->name << " of game " << g->name << "\n";
                cout << "roms size  = " << region->roms.size() << '\n';
                cout << "frac count = " << frac.count << '\n';
                continue;
            }
            const int roms_size = region->roms.size();
            ROM** roms = new ROM*[roms_size];
            int aux=0;
            int step=roms_size/frac.count;
            for( ROM* r : region->roms ) roms[aux++] = r;
            // Dump ROMs
            for( aux=0; aux<roms_size/frac.count; aux++ ) {
                Node& inter=n.add("interleave");
                inter.add_attr("output",frac_output);
                for( int chunk=0; chunk<frac.count; chunk++) {
                    ROM*r = roms[aux+chunk*step];
                    Node& part = inter.add("part");
                    part.add_attr("name",r->name);
                    part.add_attr("crc",r->crc);
                    char *mapping = new char[frac.count+1];
                    for( int k=0; k<frac.count; k++ ) mapping[k]='0';
                    mapping[frac.count]=0; // string end
                    mapping[frac.count-1-chunk]='1';
                    // Transform the single byte map to multi byte
                    string multimap;
                    if( frac.step==1 ) {
                        multimap=mapping;
                    } else { // only supports frac.step==2 right now
                        for( int k=0; k<frac.count; k++ ) {
                            if(mapping[k]=='0')
                                multimap += "00";
                            else
                                multimap += "21";
                        }
                    }
                    part.add_attr("map",multimap.c_str() );
                    delete[] mapping;
                    dumped += r->size;
                }
            }
            delete[] roms;
        }
    }
    if(header) header->set_offset( string("EOF"),dumped);
    if(qsound) {
        char title[128];
        snprintf(title,128,"QSound firmware - starts at 0x%X", dumped );
        n.comment(title);
        Node& part = n.add("part");
        part.add_attr("name","dl-1425.bin");
        part.add_attr("crc","d6cf5ef5");
        part.add_attr("length","0x2000");
        dumped+=0x2000;
    }
    char endsize[128];
    snprintf(endsize,128,"Total 0x%X bytes - %d kBytes",dumped,dumped>>10);
    n.comment(endsize);
    // Process header
    if( header ) {
        stringstream ss;
        int *b = header->data();
        for( int k=0; k<header->get_size(); k++ ) {
            if( k>0 && (k%8==0) )
                ss << '\n';
            if( k%8==0 ) ss << "        ";
            ss << hex << setfill('0') << setw(2)  << b[k] << ' ';
        }
        Node& h = n.add_front("part", ss.str() );
    }
}

void makeDIP( Node& root, Game* g, string& dipbase, shift_list& shifts ) {
    ListDIPs& dips=g->getDIPs();
    int base=-8;
    bool ommit_parenthesis=true;
    string last_tag, last_location;
    int cur_shift=0;
    int dip_width=8;
    if( dips.size() ) {
        Node& n = root.add("switches");
        n.add_attr("base",dipbase);
        n.add_attr("default", dipbase=="8" ? "FF,FF,FF" : "FF,FF");
        for( DIPsw* dip : dips ) {
            if( dip->tag != last_tag /*|| dip->location != last_location*/ ) {
                n.comment( dip->tag );
                //if( last_tag.size() )
                base+=dip_width;
                dip_width = 8; // restores it for next DIP SW
                last_tag = dip->tag;
                last_location = dip->location;
                // cout << "base = " << base << "\ntag " << dip->tag << "\nlocation " << dip->location << '\n';
                // Look for shift
                cur_shift = 0;
                for( auto& k : shifts) {
                    if( k.name == dip->tag ) {
                        cur_shift = k.shift;
                        break;
                    }
                }
            }
            Node &dipnode = n.add("dip");
            dipnode.add_attr("name",dip->name);
            // Bits
            int bit0 = base;
            int bit1 = base;
            int m    = dip->mask;
            int k;
            for( k=0; k<32; k++ ) {
                if( (m&1) == 0 ) {
                    m>>=1;
                    bit0++;
                }
                else
                    break;
            }
            if( bit0-base > 8 ) dip_width = 16;
            for( bit1=bit0; k<32;k++ ) {
                if( (m&1) == 1 ) {
                    m>>=1;
                    bit1++;
                }
                else
                    break;
            }
            --bit1;
            //if( bit0 > base ) bit0-=base;
            //if( bit1 > base ) bit1-=base;
            // apply shift
            bit0 -= cur_shift;
            bit1 -= cur_shift;
            stringstream bits;
            if( bit1==bit0 )
                bits << dec << bit0;
            else
                bits << dec << bit0 << "," << bit1;
            dipnode.add_attr("bits",bits.str());
            // Add DIP configuration values
            stringstream ids;
            for( DIPvalue& dval : dip->values ) {
                string aux = dval.name;
                if( ommit_parenthesis ) {
                    while(1) {
                        int x = aux.find_first_of('(');
                        if( x!=string::npos) {
                            int y = aux.find_first_of(')');
                            if( y!=string::npos) {
                                aux = aux.substr(0,x)+aux.substr(y+1);
                            } else break;
                        } else break;
                    }
                }
                replace( aux, "0000", "0k");
                replace( aux, " Coins", "");
                replace( aux, " Coin", "");
                replace( aux, " Credits", "");
                replace( aux, " Credit", "");
                if( aux[aux.length()-1]==' ' ) {
                    aux.erase( aux.end()-1 );
                }
                ids << aux << ',';
            }
            string ids_str = ids.str();
            ids_str.erase( ids_str.length()-1, 1 ); // delete final comma
            dipnode.add_attr("ids",ids_str);
        }
    }
}

void makeJOY( Node& root, Game* g, string buttons ) {
    Node& n = root.add("buttons");
    if( buttons.size()==0 ) {
        buttons="Fire Jump";
    }
    string names,mapped;
    int count=0;
    const char *pad_buttons[]={"Y","X","B","A","L","R","Select","Start"};
    size_t last=0, pos = buttons.find_first_of(' ');
    do {
        if(count>0) {
            names+=",";
            mapped+=",";
        }
        buttons[last] = toupper( buttons[last] );
        names  += pos==string::npos ? buttons.substr(last) : buttons.substr(last,pos-last);
        mapped += pad_buttons[count];
        if(pos==string::npos) break;
        last=pos+1;
        pos=buttons.find_first_of(' ', last);
        count++;
    } while(true);
    if( count>6 ) {
        cout << "ERROR: more than six buttons were defined. That is not supported yet.\n";
        cout << "       start, coin and pause will not be automatically added\n";
    } else if(count>4) {
        names +=",Start,Coin,Pause";
        mapped+=",Select,Start,-";
    } else {
        names +=",Start,Coin,Pause";
        mapped+=",R,L,Start";
    }
    n.add_attr("names",names.c_str());
    n.add_attr("default",mapped.c_str());
}

void makeMOD( Node& root, Game* g, int mod_or ) {
    int mod_value = mod_or;
    if( g->rotate!=0 ) {
        root.comment("Vertical game");
        mod_value |= 1;
    }
    char buf[4];
    snprintf(buf,4,"%02X",mod_value);
    Node& mod=root.add("rom");
    mod.add_attr("index","1");
    Node& part = mod.add("part",buf);

}
/*
void makeQSound( Node& root ) {
    Node& rom = root.add("rom");
    rom.add_attr("index","0");
    rom.add_attr("zip","qsound.zip");
    rom.add_attr("md5","None");
    Node& part = rom.add("part");
    part.add_attr("name","dl-1425.bin");
    part.add_attr("crc","d6cf5ef5");
    part.add_attr("length","0x2000");
}*/

void MRAmaker::makeMRA( Game* g ) {
    string indent;
    Node root("misterromdescription");

    Node& about = root.add("about","");
    about.add_attr("author","jotego");
    about.add_attr("webpage","https://patreon.com/topapate");
    about.add_attr("source","https://github.com/jotego");
    about.add_attr("twitter","@topapate");

    root.add("name",g->description);
    root.add("setname",g->name);
    if( rbf.length()>0 ) {
        root.add("rbf",rbf);
    }

    makeROM( root, g );
    // if( qsound ) makeQSound( root );
    makeMOD( root, g, mod_or );
    makeNVRAM( root );
    makeDIP( root, g, dipbase, shifts );
    makeJOY( root, g, buttons );

    string fout_name = g->description;
    string auxfolder = altfolder;
    clean_filename(fout_name);
    fout_name+=".mra";
    if( !g->cloneof.size() ) {
        auxfolder = "";
    }
    fout_name = outdir +"/" + auxfolder + "/" + fout_name;
    ofstream fout(fout_name);
    if( !fout.good() ) {
        cout << "ERROR: cannot create " << fout_name << '\n';
        return;
    }
    fout <<
"<!--          FPGA compatible core of arcade hardware by Jotego\n"
"\n"
"              This core is available for hardware compatible with MiST and MiSTer\n"
"              Other FPGA systems may be supported by the time you read this.\n"
"              This work is not mantained by the MiSTer project. Please contact the\n"
"              core author for issues and updates.\n"
"\n"
"              (c) Jose Tejada, 2020. Please support the author\n"
"              Patreon: https://patreon.com/topapate\n"
"              Paypal:  https://paypal.me/topapate\n"
"\n"
"              The author does not endorse or participate in illegal distribution\n"
"              of copyrighted material. This work can be used with legally\n"
"              obtained ROM dumps or with compatible homebrew software\n"
"\n"
"              This file license is GNU GPLv2.\n"
"              You can read the whole license file in\n"
"              https://opensource.org/licenses/gpl-2.0.php\n"
"\n"
"-->\n\n";
    root.dump(fout);
}

void MRAmaker::makeNVRAM( class Node& root ) {
    Node &n = root.add("nvram");
    char sz[32];
    sprintf(sz,"%d",nvram_size);
    n.add_attr("index","2");
    n.add_attr("size",sz);
}

Node& Node::add( string n, string v ) {
    Node *nd = new Node(n, v);
    nodes.push_back(nd);
    return *nd;
}

Node& Node::add_front( string n, string v ) {
    Node *nd = new Node(n, v);
    nodes.push_front(nd);
    return *nd;
}

void Node::add_attr( string n, string v) {
    Attr* a = new Attr({n,v});
    attrs.push_back(a);
}

void Node::add_attr( string n, int v) {
    char s[128];
    sprintf(s,"%d",v);
    add_attr( n, s );
}

void Node::comment( string v ) {
    Node *nd = new Node(v);
    nodes.push_back(nd);
    nd->is_comment = true;
}

void Node::dump(ostream& os, string indent ) {
    if( is_comment ) {
        os << indent << "<!-- " << name << " -->\n";
    }
    else {
        os << indent << "<" << name;
        if( attrs.size() ) {
            for( Attr* a : attrs ) {
                os << " " << a->name << "=\"" << a->value << '\"';
            }
        }
        if( nodes.size() || value.size() ) {
            os << ">";
            if( !nodes.size()) {
                string aux = value.size()>80 ? "\n" : "";
                os << aux;
                os << value << aux;
                if( value.find_first_of('\n')!=string::npos ) os << indent;
            } else {
                os << '\n';
                for( Node* n : nodes ) {
                    n->dump(os, indent+"    ");
                }
                os << indent;
            }
            os << "</" << name << ">\n";
        } else {
            os << "/>\n";
        }
    }
}

Node::~Node() {
    for( Node* n: nodes ) delete n;
    for( Attr* a: attrs ) delete a;
}

void clean_filename( string& fname ) {
    if( fname.size()==0 ) {
        fname="no-description";
        cout << "ERROR: no description in XML file\n";
        return;
    }
    char *s = new char[ fname.size()+1 ];
    char *c = s;
    for( int k=0; k<fname.size(); k++ ) {
        if( fname[k]=='/' ) {
            *c++='-';
        } else
        if( fname[k]>=32 && fname[k]!='\'' && fname[k]!=':') {
            *c++=fname[k];
        }
    }
    *c=0;
    // Remove trailing blanks
    while( *--c==' ' || *c=='\t' ) {
        *c=0;
    }
    fname=s;
    delete[]s;
}

Header::Header(int size, int fill ) {
    buf = new int[size];
    _size = size;
    pos=0;
    for( int k=0; k<size; k++ ) buf[k]=fill;
    reverse = false;
}

Header::~Header() {
    delete []buf;
    buf=NULL;
}

void Header::push(int v) {
    if(pos<_size-1) buf[pos++] = v;
}

bool Header::set_pointer( int p ) {
    if( p<_size-1 ) {
        pos=p;
        return true;
    } else
        return false;
}

bool Header::set_offset( const string& s, int offset ) {
    int k=0;
    bool found=false;
    while( k<regions.size() ) {
        if( regions[k]==s ) {
            found=true;
            break;
        }
        k++;
    }
    if( found || s=="EOF") {
        int j=offset_lut+k*2;
        if( j+2 >= _size ) return false;
        offset>>=_offsetbits;
        if( !reverse ) {
            buf[j++] = (offset>>8)&0xff;
            buf[j]   =  offset    &0xff;
        } else {
            buf[j++] =  offset    &0xff;
            buf[j]   = (offset>>8)&0xff;
        }
        return true;
    }
    return false;
}

Node::Node( string n, string v ) : name(n), value(v), is_comment(false) {
    while(v.back()==' ') v.pop_back();
}